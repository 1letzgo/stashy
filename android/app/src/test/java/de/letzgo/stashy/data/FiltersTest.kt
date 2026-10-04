package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FiltersTest {
    private fun obj(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    @Test fun sanitizeUnwrapsWebUiItemsAndExcluded() {
        val ui = obj("""{"tags":{"value":{"items":[{"id":"1","label":"A"}],"excluded":[{"id":"2","label":"B"}],"depth":-1},"modifier":"INCLUDES"}}""")
        val out = FilterMapper.sanitize(ui)
        assertEquals(obj("""{"tags":{"value":["1"],"modifier":"INCLUDES","depth":-1,"excludes":["2"]}}"""), out)
    }

    @Test fun sanitizeLegacyCriteriaArrayMapsRatingAndCastsInts() {
        val legacy = obj("""{"c":[{"id":"rating","value":"60","modifier":"GREATER_THAN","type":"x"}],"sort":"date"}""")
        val out = FilterMapper.sanitize(legacy)
        assertEquals(obj("""{"rating100":{"value":60,"modifier":"GREATER_THAN"}}"""), out)
    }

    @Test fun sanitizeFlattensBooleansAndStrings() {
        val ui = obj("""{"organized":{"value":"true","modifier":"EQUALS"},"is_missing":{"value":"title","modifier":"EQUALS"},"orientation":{"value":["landscape"],"modifier":"INCLUDES"}}""")
        val out = FilterMapper.sanitize(ui)
        assertEquals(JsonPrimitive(true), out["organized"])
        assertEquals(JsonPrimitive("title"), out["is_missing"])
        assertEquals(obj("""{"value":["LANDSCAPE"]}"""), out["orientation"])
    }

    @Test fun sanitizeDropsEmptyIncludesButKeepsExcludeOnlyAndIsNull() {
        val out = FilterMapper.sanitize(obj("""{"tags":{"value":[],"modifier":"INCLUDES"},"studios":{"value":[],"excludes":["3"],"modifier":"INCLUDES"},"performers":{"modifier":"IS_NULL"}}"""))
        assertNull(out["tags"])
        assertEquals(listOf("3"), FilterMapper.idStrings(out["studios"]!!.jsonObject["excludes"]))
        assertTrue(out.containsKey("performers"))
    }

    @Test fun sanitizeMarkerNestsSceneKeysFromCriteriaArray() {
        val out = FilterMapper.sanitize(obj("""{"c":[{"id":"organized","value":true}]}"""), isMarker = true)
        assertEquals(JsonPrimitive(true), out["scene_filter"]!!.jsonObject["organized"])
    }

    @Test fun uiObjectFilterWritesWebUiShape() {
        val out = FilterMapper.uiObjectFilter(obj("""{"tags":{"value":["1"],"excludes":["2"],"modifier":"INCLUDES","depth":0},"organized":true}"""), mapOf("1" to "One"))
        assertEquals(
            obj("""{"tags":{"value":{"items":[{"id":"1","label":"One"}],"excluded":[{"id":"2","label":"2"}],"depth":0},"modifier":"INCLUDES"},"organized":{"value":"true","modifier":"EQUALS"}}"""),
            out,
        )
        // Round trip back to the query shape.
        assertEquals(obj("""{"tags":{"value":["1"],"modifier":"INCLUDES","depth":0,"excludes":["2"]},"organized":true}"""), FilterMapper.sanitize(out))
    }

    @Test fun idStringsHandlesNumbersObjectsAndItems() {
        assertEquals(listOf("5", "7"), FilterMapper.idStrings(obj("""{"a":[5,{"id":"7"}]}""")["a"]))
        assertEquals(listOf("9"), FilterMapper.idStrings(obj("""{"a":{"items":[{"id":9}]}}""")["a"]))
        assertEquals(emptyList<String>(), FilterMapper.idStrings(null))
    }

    @Test fun documentStripsIncompleteCriteriaAndFillsModifier() {
        val doc = CriteriaDocument(FilterMode.Scenes)
        doc.setCriterion("title", obj("""{"value":"","modifier":"INCLUDES"}"""))
        doc.setCriterion("studios", obj("""{"value":["4"]}"""))
        doc.setCriterion("o_counter", obj("""{"modifier":"NOT_NULL"}"""))
        doc.setCriterion("rating100", obj("""{"value_text":"1.","modifier":"EQUALS"}"""))
        val s = doc.sanitizedObjectFilter
        assertNull(s["title"])
        assertNull(s["rating100"])
        assertEquals(JsonPrimitive("INCLUDES"), s["studios"]!!.jsonObject["modifier"])
        // IS_NULL / NOT_NULL int criteria get value 0 (IntCriterionInput requires it).
        assertEquals(JsonPrimitive(0), s["o_counter"]!!.jsonObject["value"])
        assertEquals(2, doc.activeCriterionCount)
    }

    @Test fun documentPinsDefaultsFirstAndAppendsNewKeys() {
        val doc = CriteriaDocument(FilterMode.Performers, pinsDefaults = true)
        doc.setCriterion("weight", obj("""{"value":50,"modifier":"GREATER_THAN"}"""))
        doc.setCriterion("age", obj("""{"value":30,"modifier":"LESS_THAN"}"""))
        val keys = doc.displayedCriterionKeys()
        assertEquals(FilterFieldCatalog.defaultCriterionKeys(FilterMode.Performers), keys.take(8))
        assertEquals("weight", keys.last())
    }

    @Test fun documentGroupsChangeTypeKeepsContents() {
        val doc = CriteriaDocument(FilterMode.Scenes, obj("""{"OR":{"organized":true}}"""))
        doc.changeGroupType(emptyList(), "OR", "NOT")
        assertNull(doc.objectFilter["OR"])
        assertEquals(JsonPrimitive(true), doc.node(listOf("NOT"))["organized"])
        assertEquals(listOf("NOT"), doc.groupKeys(emptyList()))
    }

    @Test fun mergedForSaveRemovesChipKeysTheUserCleared() {
        val base = SavedFilter("1", "Base", "SCENES", objectFilter = obj("""{"organized":{"value":"true","modifier":"EQUALS"},"tags":{"value":{"items":[{"id":"1"}]},"modifier":"INCLUDES"}}"""))
        val merged = mergedObjectFilterForSave(base, obj("""{"rating100":{"value":80,"modifier":"GREATER_THAN"}}"""), previousLive = obj("""{"tags":{}}"""))
        assertEquals(setOf("organized", "rating100"), merged.keys)
    }

    @Test fun savedFilterMetadataAndSortResolution() {
        val f = SavedFilter(
            "7", "Mine", "PERFORMERS",
            findFilter = obj("""{"sort":"random_42","direction":"DESC"}"""),
            uiOptions = obj("""{"stashy":{"sortRaw":"oCountDesc","liveFragment":{"filter_favorites":true},"baseSavedFilterId":"3"}}"""),
        )
        val meta = f.stashyMetadata!!
        assertEquals("3", meta.baseSavedFilterId)
        assertEquals("oCountDesc", f.resolvedSort(FilterMode.Performers)?.raw)
        val noMeta = f.copy(uiOptions = null)
        assertEquals("random", noMeta.resolvedSort(FilterMode.Performers)?.raw)
        val legacy = SavedFilter("8", "Old", "SCENES", filter = """{"sortby":"rating100","sortdir":"asc"}""")
        assertEquals("ratingAsc", legacy.resolvedSort(FilterMode.Scenes)?.raw)
    }

    @Test fun sortOptionsMirrorIosFieldsAndPickerRules() {
        val perf = SortCatalog.option(FilterMode.Performers, "sceneCountDesc")!!
        assertEquals("scenes_count", perf.field)
        assertEquals("imageCountDesc", SortCatalog.optionAfterPickingField(FilterMode.Performers, perf, "images_count")!!.raw)
        val asc = SortCatalog.optionFor(FilterMode.Performers, "name", true)!!
        assertEquals("nameAsc", asc.raw)
        assertEquals("birthdateAsc", SortCatalog.optionAfterPickingField(FilterMode.Performers, asc, "birthdate")!!.raw)
        val random = SortCatalog.option(FilterMode.Scenes, "random")!!
        assertEquals("dateDesc", SortCatalog.optionAfterPickingField(FilterMode.Scenes, random, "date")!!.raw)
        assertEquals("scene_markers_count", SortCatalog.option(FilterMode.Tags, "markerCountAsc")!!.field)
        assertTrue(RandomSeeds.sortField(FilterMode.Scenes, random).startsWith("random_"))
        assertEquals("date", RandomSeeds.sortField(FilterMode.Scenes, SortCatalog.option(FilterMode.Scenes, "dateAsc")!!))
        // Every sheet field kind maps to existing options in both directions.
        FilterMode.entries.forEach { mode ->
            SortCatalog.fieldKinds(mode).forEach { k ->
                if (k.field != "random") {
                    assertTrue("$mode ${k.field}", SortCatalog.optionFor(mode, k.field, true) != null)
                    assertTrue("$mode ${k.field}", SortCatalog.optionFor(mode, k.field, false) != null)
                }
            }
        }
        assertEquals(PerformerBadgeType.OCount, PerformerBadgeType.forSort(SortCatalog.option(FilterMode.Performers, "oCountAsc")!!))
    }

    @Test fun presetTagsAndLocalPresetJson() {
        assertEquals("server:12", ListLivePresetTag.serverRow("12"))
        assertEquals("12", ListLivePresetTag.parseServerId("server:12"))
        assertNull(ListLivePresetTag.parseLocalId("server:12"))
        val p = LocalFilterPreset.create("B", "nameAsc", null, obj("""{"favorite":true}"""), id = "U1")
        val list = LocalFilterPresetStore.upserted(listOf(LocalFilterPreset.create("a", "nameAsc", null, JsonObject(emptyMap()), id = "U0")), p)
        assertEquals(listOf("a", "B"), list.map { it.name })
        val decoded = LocalFilterPresetStore.decode(LocalFilterPresetStore.encode(list))
        assertEquals(list, decoded)
        assertEquals(JsonPrimitive(true), decoded[1].liveFragment["favorite"])
        // iOS JSONEncoder shape (Date as reference-date seconds) decodes too.
        val ios = """[{"id":"6F1","name":"X","createdAt":781234567.5,"sortRaw":"dateDesc","liveFragmentJSON":"{}"}]"""
        assertEquals("dateDesc", LocalFilterPresetStore.decode(ios).single().sortRaw)
    }

    @Test fun catalogQueryMergesBaseLiveAndScope() {
        val base = SavedFilter("1", "B", "GALLERIES", objectFilter = obj("""{"organized":{"value":"false","modifier":"EQUALS"},"rating100":{"value":20,"modifier":"GREATER_THAN"}}"""))
        val q = CatalogQuery(
            FilterMode.Galleries, SortCatalog.option(FilterMode.Galleries, "dateDesc")!!, base = base,
            live = obj("""{"rating100":{"value":60,"modifier":"GREATER_THAN"}}"""),
            scope = JsonObject(mapOf("performers" to includesCriterion("9"))),
        )
        val f = q.entityFilter()!!
        assertEquals(JsonPrimitive(false), f["organized"])
        assertEquals(JsonPrimitive(60), f["rating100"]!!.jsonObject["value"])
        assertEquals(listOf("9"), FilterMapper.idStrings(f["performers"]!!.jsonObject["value"]))
        assertNull(CatalogQuery(FilterMode.Scenes, SortCatalog.scenes[1]).entityFilter())
    }

    @Test fun markerQueryHoistsSceneKeys() {
        val q = CatalogQuery(
            FilterMode.SceneMarkers, SortCatalog.markers[1],
            live = obj("""{"tags":{"value":["1"],"modifier":"INCLUDES"},"scene_filter":{"organized":true},"rating100":{"value":40,"modifier":"GREATER_THAN"}}"""),
        )
        val f = q.entityFilter()!!
        assertEquals(listOf("1"), FilterMapper.idStrings(f["tags"]!!.jsonObject["value"]))
        val scene = f["scene_filter"]!!.jsonObject
        assertEquals(JsonPrimitive(true), scene["organized"])
        assertTrue(scene.containsKey("rating100"))
        assertFalse(f.containsKey("rating100"))
    }

    @Test fun saveInputMatchesIosShape() {
        val input = SavedFiltersRepository.saveInput(
            FilterMode.Tags, "4", " Faves ", SortCatalog.option(FilterMode.Tags, "nameAsc")!!,
            obj("""{"favorite":true}"""), obj("""{"favorite":true}"""), baseSavedFilterId = "2",
        )
        assertEquals(JsonPrimitive("4"), input["id"])
        assertEquals(JsonPrimitive("TAGS"), input["mode"])
        assertEquals(JsonPrimitive("Faves"), input["name"])
        assertEquals(obj("""{"sort":"name","direction":"ASC"}"""), input["find_filter"])
        assertEquals(obj("""{"favorite":{"value":"true","modifier":"EQUALS"}}"""), input["object_filter"])
        val stashy = input["ui_options"]!!.jsonObject["stashy"]!!.jsonObject
        assertEquals(JsonPrimitive("nameAsc"), stashy["sortRaw"])
        assertEquals(JsonPrimitive("2"), stashy["baseSavedFilterId"])
    }

    @Test fun summaryTexts() {
        val multi = FilterFieldCatalog.field("tags", FilterMode.Scenes)!!
        assertEquals("Any", FilterCriterionSummary.text(multi, null))
        assertEquals("2 selected, 1 excluded", FilterCriterionSummary.text(multi, obj("""{"value":["1","2"],"excludes":["3"],"modifier":"INCLUDES"}""")))
        val rating = FilterFieldCatalog.field("rating100", FilterMode.Scenes)!!
        assertEquals("> 60", FilterCriterionSummary.text(rating, obj("""{"value":60,"modifier":"GREATER_THAN"}""")))
        assertEquals("20 – 40", FilterCriterionSummary.text(rating, obj("""{"value":20,"value2":40,"modifier":"BETWEEN"}""")))
        val gender = FilterFieldCatalog.field("gender", FilterMode.Performers)!!
        assertEquals("Transgender Female", FilterCriterionSummary.text(gender, obj("""{"value_list":["TRANSGENDER_FEMALE"],"modifier":"INCLUDES"}""")))
        assertEquals("Not set", FilterCriterionSummary.text(gender, obj("""{"modifier":"IS_NULL"}""")))
        assertEquals("Yes", FilterCriterionSummary.text(FilterFieldCatalog.field("organized", FilterMode.Scenes)!!, JsonPrimitive(true)))
        assertEquals(JsonArray(emptyList()), (CriterionKind.multi.defaultValue(FilterMode.Scenes) as JsonObject)["value"])
    }

    @Test fun pickerKindsFollowIosRules() {
        assertEquals(PickerKind.PerformerTags, PickerKind.forCriterion("performer_tags", FilterMode.Scenes))
        assertEquals(PickerKind.Tags, PickerKind.forCriterion("scene_tags", FilterMode.SceneMarkers))
        assertEquals(PickerKind.MarkerTags, PickerKind.forCriterion("tags", FilterMode.SceneMarkers))
        assertEquals(PickerKind.ImageStudios, PickerKind.forCriterion("studios", FilterMode.Images))
        assertEquals(PickerKind.AllTags, PickerKind.forCriterion("parents", FilterMode.Tags))
        assertEquals(PickerKind.Groups, PickerKind.forCriterion("containing_groups", FilterMode.Groups))
        assertNull(PickerKind.forCriterion("scenes", FilterMode.Galleries))
    }

    @Test fun tabConfigDecodesIosJsonAndColumns() {
        val ios = """[{"id":"performers","isVisible":true,"sortOrder":2,"sortOption":"oCountDesc","defaultFilterId":"5","defaultFilterName":"F"},{"id":"dashboard","isVisible":true,"sortOrder":0}]"""
        val tabs = CatalogPrefs.decodeTabs(ios)!!
        assertEquals("oCountDesc", tabs[0].defaultSortOption)
        assertEquals("5", tabs[0].defaultFilterId)
        assertTrue(CatalogPrefs.encodeTabs(tabs).contains("\"sortOption\":\"oCountDesc\""))
        assertEquals(1, CatalogCardColumns.One.columnCount(380f))
        assertEquals(2, CatalogCardColumns.Two.columnCount(380f))
        assertEquals(2, CatalogCardColumns.One.columnCount(1000f))
        assertEquals(2, adaptiveColumnCount(380f))
        assertEquals(5, adaptiveColumnCount(1100f))
        assertEquals(2, adaptiveColumnCount(0f))
    }
}
