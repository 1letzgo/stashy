
import { useApolloClient, type ApolloClient, type NormalizedCacheObject } from "@apollo/client";
import { useContext, useEffect, useMemo, useState } from "react";
import * as GQL from "stash-ui/dist/src/core/generated-graphql";
import { ListFilterModel } from "stash-ui/dist/src/models/list-filter/filter";
import { useAppStateStore } from "../store/appStateStore";
import { useWindowSize } from "./useWindowSize";
import { create } from "zustand";
import { useConditionalMemo } from "./useMemoConditional";
import { ConfigurationContext } from "stash-ui/dist/src/hooks/Config";
import { useFindSavedFilters } from "stash-ui/dist/src/core/StashService";
import useStashTvConfig from "./useStashTvConfig";

/** In Stash a filter has a different format when it's saved vs when it's used in a search. The stash codebase doesn't
 * seem to do a great job of naming these different formats to make that clear. When a filter is saved it usually just
 * referred to as a saved filter but when it's used in a search it's referred to as a by the type of entity being
 * searched, like a media item filter.
 *
 * To make this clearer we use "saved filter" to refer to a filter in its saved format (or "saved media item filter" for
 * specifically a media item filter) and "searchable filter" to refer to a filter in its searchable format (or "searchable
 * media item filter" for specifically a media item filter).
 *
 * The rest of the Stash TV codebase pretty much only deals with the searchable format so we just hide this distinction
 * and only present the searchable format outside of this file which we simply refer to as a "filter" (or "media item filter"
 * for specifically a media item filter).
 */

type SavedMediaItemFilter = GQL.SavedFilter

export type SearchableMediaItemFilter = {
  savedFilter?: SavedMediaItemFilter,
  generalFilter: GQL.FindFullScenesQueryVariables["filter"],
  isCurrentFilter: boolean,
} & (
  {
    entityFilter: GQL.FindFullScenesQueryVariables["scene_filter"]
    entityType: "scene"
  } |
  {
    entityFilter: GQL.FindSceneMarkersForTvQueryVariables["scene_marker_filter"]
    entityType: "marker"
  }
)

type EntityType = SearchableMediaItemFilter["entityType"]

const useGlobalFilterState = create<{
  loadingResponsibilityClaimed: boolean,
  currentSavedFilter: SavedMediaItemFilter | undefined,
  loading: boolean,
  error: unknown,
  randomSeed?: number,
}>(() => ({
  loadingResponsibilityClaimed: false,
  currentSavedFilter: undefined,
  loading: false,
  error: undefined,
  randomSeed: getRandomSeed(),
}))

export function useMediaItemFilters() {
  const {
    currentSavedFilter,
    loading: mediaItemFiltersLoading,
    error: mediaItemFiltersError,
    randomSeed,
  } = useGlobalFilterState()
  const apolloClient = useApolloClient() as ApolloClient<NormalizedCacheObject>;

  const {
    configuration: {
      ui: {
        defaultFilters: {
          scenes: stashDefaultScenesFilter
        } = {}
      } = {}
    } = {},
    loading: stashConfigurationLoading
  } = useContext(ConfigurationContext)

  const {
    data: { findSavedFilters: availableSavedSceneFilters = []} = {},
    loading: loadingAvailableSavedSceneFilters,
  } = useFindSavedFilters(GQL.FilterMode.Scenes);

  const {
    data: { findSavedFilters: availableSavedMarkerFilters = []} = {},
    loading: loadingAvailableSavedMarkerFilters,
  } = useFindSavedFilters(GQL.FilterMode.SceneMarkers);

  const loadingDataRequiredBeforeLoadingCurrentFilter = stashConfigurationLoading || loadingAvailableSavedSceneFilters || loadingAvailableSavedMarkerFilters;

  const { isRandomised, onlyShowMatchingOrientation, currentFilterId } = useAppStateStore();
  const { orientation } = useWindowSize()

  let limitOrientation: "landscape" | "portrait" | undefined = undefined
  if (onlyShowMatchingOrientation && orientation !== "square") {
    limitOrientation = orientation
  }

  const currentSearchableFilter = useMemo(
    () => currentSavedFilter ? convertSavedToSearchableFilter(currentSavedFilter) : undefined,
    [currentSavedFilter, isRandomised && randomSeed, limitOrientation]
  )
  const lastLoadedCurrentMediaItemFilter = useConditionalMemo(
    () => currentSearchableFilter,
    [currentSearchableFilter],
    !loadingDataRequiredBeforeLoadingCurrentFilter && !mediaItemFiltersLoading
  )

  const [isResponsibleForLoading, setIsResponsibleForLoading] = useState(false);

  // Load default filter on initial load.
  useEffect(() => {
    if (useGlobalFilterState.getState().loadingResponsibilityClaimed) return;
    useGlobalFilterState.setState({ loadingResponsibilityClaimed: true, loading: true });
    setIsResponsibleForLoading(true);
  }, [])

  useEffect(() => {
    if (!isResponsibleForLoading || loadingDataRequiredBeforeLoadingCurrentFilter) return;

    // Place most of the logic into a separate function so we can use async/await
    async function setCurrentMediaItemFilterOnInitialLoad() {
      try {
        if (currentFilterId) {
          await setCurrentMediaItemFilterById(currentFilterId)
        } else if (stashDefaultScenesFilter)  {
          // No default filter ID set for Stash TV specifically so we use the default Stash filter
          useGlobalFilterState.setState({
            currentSavedFilter: {
              ...stashDefaultScenesFilter,
              filter: '', // The filter prop is deprecated in favour of find_filter and object_filter, and it's not
                // provided when getting a default saved filter so we can safely set an empty string here.
            }
          })
        } else {
          // No Stash default filter so we should use an empty filter
          useGlobalFilterState.setState({
            currentSavedFilter: {
              id: "",
              mode: GQL.FilterMode.Scenes,
              name: "",
              filter: "", // See the comment above about the `filter` prop
            }
          })
        }
      } catch (error) {
        useGlobalFilterState.setState({ error });
      }
      useGlobalFilterState.setState({ loading: false });
    }
    setCurrentMediaItemFilterOnInitialLoad()
  }, [isResponsibleForLoading, loadingDataRequiredBeforeLoadingCurrentFilter, currentFilterId, stashDefaultScenesFilter]);

  async function setCurrentMediaItemFilterById(id: string) {
    useGlobalFilterState.setState({ loading: true });
    const {name, entityType} = availableSavedFilters.find(f => f.id === id) || {}
    if (name && entityType) {
      // Optimistically set the filter so change is immediately reflected in the UI
      useGlobalFilterState.setState({
        currentSavedFilter: {
          id,
          mode: entityType === "scene" ? GQL.FilterMode.Scenes : GQL.FilterMode.SceneMarkers,
          name: name,
          filter: '', // See the comment above about the `filter` prop
        }
      });
    }
    const mediaItemFiltersStashResponse = await fetchSavedFilterFromStash(apolloClient, id);

    if (!mediaItemFiltersStashResponse) {
      // Stash has no record of a filter with this ID
      return undefined;
    }

    useGlobalFilterState.setState({
      randomSeed: getRandomSeed(),
      currentSavedFilter: {
        ...mediaItemFiltersStashResponse,
        filter: '', // See the comment above about the `filter` prop
      },
      loading: false,
    });
  }

  async function fetchSavedFilterFromStash(apolloClient: ApolloClient<NormalizedCacheObject>, filterId: string): Promise<GQL.SavedFilterDataFragment | null> {
    const { data } = await apolloClient.query<GQL.FindSavedFilterQuery, GQL.FindSavedFilterQueryVariables>({
      query: GQL.FindSavedFilterDocument,
      variables: { id: filterId },
    });

    return data?.findSavedFilter ?? null;
  }

  function convertSavedToSearchableFilter(
    savedFilter: SavedMediaItemFilter
  ): SearchableMediaItemFilter {
    function getGeneralFilter() {
      const filter = new ListFilterModel(savedFilter.mode)
      filter.configureFromSavedFilter(savedFilter);
      const updatedFilter = { ...filter.makeFindFilter() };

      if (updatedFilter.sort?.match(/^random_\d*$/) || isRandomised) {
        updatedFilter.sort = `random_${randomSeed}`
      }

      return updatedFilter;
    }

    function addSceneFiltersMods(sceneFilter: GQL.FindFullScenesQueryVariables["scene_filter"]) {
      if (limitOrientation) {
        sceneFilter = sceneFilter || {};
        sceneFilter.orientation = {
          "value": [
            limitOrientation.toUpperCase() as GQL.OrientationEnum,
            "SQUARE" as GQL.OrientationEnum
          ]
        };
      }
      return sceneFilter;
    }

    function getSceneFilter() {
      const filter = new ListFilterModel(savedFilter.mode)
      filter.configureFromSavedFilter(savedFilter);

      return addSceneFiltersMods(
        filter.makeFilter()
      )
    }

    function getMarkerFilter() {
      const filter = new ListFilterModel(savedFilter.mode)
      filter.configureFromSavedFilter(savedFilter);

      const markerFilter: GQL.FindSceneMarkersForTvQueryVariables["scene_marker_filter"] = filter.makeFilter();
      markerFilter.scene_filter = addSceneFiltersMods(markerFilter.scene_filter);

      return markerFilter;
    }

    const sharedProps = {
      savedFilter,
      generalFilter: getGeneralFilter(),
      get isCurrentFilter() {
        return savedFilter.id === currentFilterId;
      }
    }

    if (savedFilter.mode === GQL.FilterMode.Scenes) {
      return {
        ...sharedProps,
        entityFilter: getSceneFilter(),
        entityType: "scene",
      }
    } else if (savedFilter.mode === GQL.FilterMode.SceneMarkers) {
      return {
        ...sharedProps,
        entityFilter: getMarkerFilter(),
        entityType: "marker",
      }
    } else {
      throw new Error(`Unsupported saved filter mode: ${savedFilter.mode}`);
    }
  }

  const availableSavedFilters = useMemo(
    () => {
      const savedFilters = []
      const savedFiltersByType: [EntityType, {id: string, name: string}[]][] = [
        ["scene", availableSavedSceneFilters],
        ["marker", availableSavedMarkerFilters],
      ]
      for (const [entityType, savedFiltersOfType] of savedFiltersByType) {
        for (const savedFilter of savedFiltersOfType) {
          savedFilters.push({
            ...savedFilter,
            isCurrentFilter: savedFilter.id === currentFilterId,
            entityType
          })
        }
      }
      return savedFilters;
    },
    [availableSavedSceneFilters, availableSavedMarkerFilters, currentFilterId]
  );

  return {
    mediaItemFiltersLoading: loadingDataRequiredBeforeLoadingCurrentFilter || mediaItemFiltersLoading,
    mediaItemFiltersError,
    currentMediaItemFilter: currentSearchableFilter,
    lastLoadedCurrentMediaItemFilter,
    clearCurrentMediaItemFilter: () => useGlobalFilterState.setState({ currentSavedFilter: undefined }),
    setCurrentMediaItemFilterById,
    availableSavedFilters
  }
}

function getRandomSeed() {
  return Math.round(Math.random() * 1000000)
};