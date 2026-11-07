package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Saved filters round-trip with Stash's web UI: `object_filter` is written in the web UI's own
 * format (`FilterMapper.savedObjectFilter`) and read back into the GraphQL query format
 * (`FilterMapper.sanitize`). Same expectations as the iOS `FilterMapper`.
 */
class FilterSavedFormatTest {
    private fun obj(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    /** Ids repeat across entity types: tag 5 and studio 5 must keep their own names. */
    private val labels: (FilterMapper.LabelKind, String) -> String? = { kind, id ->
        when (kind to id) {
            FilterMapper.LabelKind.Tag to "1" -> "Blonde"
            FilterMapper.LabelKind.Tag to "5" -> "Tag Five"
            FilterMapper.LabelKind.Studio to "5" -> "Studio Five"
            FilterMapper.LabelKind.Studio to "3" -> "Parent Studio"
            FilterMapper.LabelKind.Tag to "2" -> "Parent Tag"
            FilterMapper.LabelKind.Performer to "7" -> "Jane"
            FilterMapper.LabelKind.Folder to "11" -> "/media/a"
            else -> null
        }
    }

    private val sceneQuery = """{
        "tags":{"value":["1"],"excludes":["2"],"modifier":"INCLUDES","depth":-1},
        "performers":{"value":["7"],"modifier":"INCLUDES_ALL"},
        "studios":{"value":["5"],"modifier":"INCLUDES","depth":0},
        "galleries":{"value":["9"],"modifier":"INCLUDES"},
        "resolution":{"value":"QUAD_HD","modifier":"EQUALS"},
        "orientation":{"value":["LANDSCAPE","PORTRAIT"]},
        "organized":true,
        "has_markers":"true",
        "is_missing":"cover",
        "rating100":{"value":80,"value2":100,"modifier":"BETWEEN"},
        "created_at":{"value":"2024-01-31T13:45","modifier":"GREATER_THAN"},
        "date":{"value":"2024-01-01","value2":"2024-12-31","modifier":"BETWEEN"},
        "title":{"value":"foo","modifier":"INCLUDES"},
        "captions":{"value":"en","modifier":"INCLUDES"},
        "stash_id_endpoint":{"endpoint":"https://stashdb.org/graphql","stash_id":"abc","modifier":"EQUALS"},
        "duplicated":{"phash":true,"distance":2},
        "phash_distance":{"value":"ab12","distance":4,"modifier":"EQUALS"},
        "files_filter":{"parent_folder":{"value":["11"],"modifier":"INCLUDES","depth":-1}}
    }"""

    // MARK: - Save (query → web UI)

    @Test fun savesScenesInWebUiFormat() {
        val saved = FilterMapper.savedObjectFilter(obj(sceneQuery), FilterMapper.Entity.Scenes, labels)
        assertEquals(
            obj(
                """{
                "tags":{"value":{"items":[{"id":"1","label":"Blonde"}],"excluded":[{"id":"2","label":"Parent Tag"}],"depth":-1},"modifier":"INCLUDES"},
                "performers":{"value":{"items":[{"id":"7","label":"Jane"}],"excluded":[]},"modifier":"INCLUDES_ALL"},
                "studios":{"value":{"items":[{"id":"5","label":"Studio Five"}],"excluded":[],"depth":0},"modifier":"INCLUDES"},
                "galleries":{"value":[{"id":"9","label":"9"}],"modifier":"INCLUDES"},
                "resolution":{"value":"1440p","modifier":"EQUALS"},
                "orientation":{"value":["Landscape","Portrait"],"modifier":"EQUALS"},
                "organized":{"value":"true","modifier":"EQUALS"},
                "has_markers":{"value":"true","modifier":"EQUALS"},
                "is_missing":{"value":"cover","modifier":"EQUALS"},
                "rating100":{"value":{"value":80,"value2":100},"modifier":"BETWEEN"},
                "created_at":{"value":{"value":"2024-01-31 13:45"},"modifier":"GREATER_THAN"},
                "date":{"value":{"value":"2024-01-01","value2":"2024-12-31"},"modifier":"BETWEEN"},
                "title":{"value":"foo","modifier":"INCLUDES"},
                "captions":{"value":"English","modifier":"INCLUDES"},
                "stash_id_endpoint":{"value":{"endpoint":"https://stashdb.org/graphql","stashID":"abc"},"modifier":"EQUALS"},
                "duplicated":{"value":{"phash":true,"distance":2},"modifier":"EQUALS"},
                "phash_distance":{"value":{"value":"ab12","distance":4},"modifier":"EQUALS"},
                "folder":{"value":{"items":[{"id":"11","label":"/media/a"}],"excluded":[],"depth":-1},"modifier":"INCLUDES"}
                }""",
            ),
            saved,
        )
    }

    @Test fun savesLegacyKeysAndAppDuplicated() {
        val saved = FilterMapper.savedObjectFilter(
            obj("""{"movies":{"value":["3"],"modifier":"INCLUDES","depth":0},"duplicated":{"duplicated":true},"is_zip":false}"""),
            FilterMapper.Entity.Scenes,
        )
        assertEquals(
            obj(
                """{"groups":{"value":{"items":[{"id":"3","label":"3"}],"excluded":[],"depth":0},"modifier":"INCLUDES"},
                "duplicated":{"value":{"phash":true},"modifier":"EQUALS"},
                "is_zip":{"value":"false","modifier":"EQUALS"}}""",
            ),
            saved,
        )
    }

    @Test fun savesPerformersInWebUiFormat() {
        val saved = FilterMapper.savedObjectFilter(
            obj(
                """{"gender":{"value_list":["FEMALE","TRANSGENDER_FEMALE"],"modifier":"INCLUDES"},
                "circumcised":{"value":["CUT"],"modifier":"INCLUDES"},
                "filter_favorites":true,
                "birthdate":{"value":"1990-01-01","modifier":"GREATER_THAN"},
                "tags":{"value":["5"],"modifier":"INCLUDES","depth":0},
                "age":{"value":25,"modifier":"LESS_THAN"},
                "country":{"value":"DE","modifier":"EQUALS"},
                "stash_id_endpoint":{"modifier":"NOT_NULL"}}""",
            ),
            FilterMapper.Entity.Performers, labels,
        )
        assertEquals(
            obj(
                """{"gender":{"value":["Female","Transgender Female"],"modifier":"INCLUDES"},
                "circumcised":{"value":["Cut"],"modifier":"INCLUDES"},
                "filter_favorites":{"value":"true","modifier":"EQUALS"},
                "birthdate":{"value":{"value":"1990-01-01"},"modifier":"GREATER_THAN"},
                "tags":{"value":{"items":[{"id":"5","label":"Tag Five"}],"excluded":[],"depth":0},"modifier":"INCLUDES"},
                "age":{"value":{"value":25},"modifier":"LESS_THAN"},
                "country":{"value":"DE","modifier":"EQUALS"},
                "stash_id_endpoint":{"value":{},"modifier":"NOT_NULL"}}""",
            ),
            saved,
        )
    }

    @Test fun savesStudioParentsAsLabeledIds() {
        val studios = FilterMapper.Entity.Studios
        assertEquals(
            obj("""{"parents":{"value":[{"id":"3","label":"Parent Studio"}],"modifier":"INCLUDES"}}"""),
            FilterMapper.savedObjectFilter(obj("""{"parents":{"value":["3"],"modifier":"INCLUDES"}}"""), studios, labels),
        )
        // No `excluded` in this shape: exclude-only becomes EXCLUDES.
        assertEquals(
            obj("""{"parents":{"value":[{"id":"4","label":"4"}],"modifier":"EXCLUDES"}}"""),
            FilterMapper.savedObjectFilter(obj("""{"parents":{"value":[],"excludes":["4"],"modifier":"INCLUDES"}}"""), studios, labels),
        )
        // Both: the raw exclude ids stay beside the items.
        assertEquals(
            obj("""{"parents":{"value":[{"id":"3","label":"Parent Studio"}],"modifier":"INCLUDES","excludes":["4"]}}"""),
            FilterMapper.savedObjectFilter(obj("""{"parents":{"value":["3"],"excludes":["4"],"modifier":"INCLUDES"}}"""), studios, labels),
        )
    }

    @Test fun savesTagParentsAsHierarchy() {
        assertEquals(
            obj("""{"parents":{"value":{"items":[{"id":"2","label":"Parent Tag"}],"excluded":[],"depth":-1},"modifier":"INCLUDES"}}"""),
            FilterMapper.savedObjectFilter(obj("""{"parents":{"value":["2"],"modifier":"INCLUDES","depth":-1}}"""), FilterMapper.Entity.Tags, labels),
        )
    }

    @Test fun saveInputUsesEntityAndPerKindLabels() {
        val input = SavedFiltersRepository.saveInput(
            FilterMode.Scenes, null, "F", SortCatalog.option(FilterMode.Scenes, "dateDesc")!!,
            obj("""{"studios":{"value":["5"],"modifier":"INCLUDES","depth":0},"resolution":{"value":"FOUR_K","modifier":"GREATER_THAN"}}"""),
            null, labels = mapOf(FilterMapper.LabelKind.Tag to mapOf("5" to "Tag Five"), FilterMapper.LabelKind.Studio to mapOf("5" to "Studio Five")),
        )
        val of = input["object_filter"]!!.jsonObject
        assertEquals(JsonPrimitive("4k"), of["resolution"]!!.jsonObject["value"])
        assertEquals(
            obj("""{"items":[{"id":"5","label":"Studio Five"}],"excluded":[],"depth":0}"""),
            of["studios"]!!.jsonObject["value"],
        )
    }

    // MARK: - Load (web UI → query)

    @Test fun loadsWebUiSceneFilter() {
        val web = obj(
            """{"resolution":{"value":"4k","modifier":"GREATER_THAN"},
            "performer_tags":{"value":{"items":[{"id":"12","label":"x"}],"excluded":[],"depth":0},"modifier":"INCLUDES"},
            "organized":{"value":"false","modifier":"EQUALS"},
            "rating100":{"value":{"value":80,"value2":100},"modifier":"BETWEEN"},
            "last_played_at":{"value":{"value":"2024-03-01 08:00","value2":"2024-03-31 23:59"},"modifier":"BETWEEN"},
            "created_at":{"value":{"value":"2024-01-31 13:45"},"modifier":"GREATER_THAN"},
            "captions":{"value":"Deutsche","modifier":"INCLUDES"},
            "galleries":{"value":[{"id":"4","label":"G"}],"modifier":"EXCLUDES"},
            "stash_id_endpoint":{"value":{"endpoint":"","stashID":"xyz"},"modifier":"EQUALS"},
            "duplicated":{"value":{"phash":true,"distance":0},"modifier":"EQUALS"},
            "phash_distance":{"value":{"value":"ab12","distance":4},"modifier":"EQUALS"},
            "folder":{"value":{"items":[{"id":"8","label":"/x"}],"excluded":[],"depth":-1},"modifier":"INCLUDES"},
            "interactive":{"value":"true","modifier":"EQUALS"},
            "has_markers":{"value":"false","modifier":"EQUALS"},
            "movies":{"value":{"items":[{"id":"6","label":"m"}],"excluded":[],"depth":0},"modifier":"INCLUDES"}}""",
        )
        assertEquals(
            obj(
                """{"resolution":{"value":"FOUR_K","modifier":"GREATER_THAN"},
                "performer_tags":{"value":["12"],"modifier":"INCLUDES","depth":0},
                "organized":false,
                "rating100":{"value":80,"value2":100,"modifier":"BETWEEN"},
                "last_played_at":{"value":"2024-03-01T08:00","value2":"2024-03-31T23:59","modifier":"BETWEEN"},
                "created_at":{"value":"2024-01-31T13:45","modifier":"GREATER_THAN"},
                "captions":{"value":"de","modifier":"INCLUDES"},
                "galleries":{"value":["4"],"modifier":"EXCLUDES"},
                "stash_id_endpoint":{"modifier":"EQUALS","stash_id":"xyz"},
                "duplicated":{"phash":true,"distance":0},
                "phash_distance":{"value":"ab12","distance":4,"modifier":"EQUALS"},
                "folder":{"value":["8"],"modifier":"INCLUDES","depth":-1},
                "interactive":true,
                "has_markers":"false",
                "groups":{"value":["6"],"modifier":"INCLUDES","depth":0}}""",
            ),
            FilterMapper.sanitize(web, entity = FilterMapper.Entity.Scenes),
        )
    }

    @Test fun loadsWebUiPerformerFilter() {
        val web = obj(
            """{"gender":{"value":["Female","Transgender Female"],"modifier":"INCLUDES"},
            "circumcised":{"value":["Uncut"],"modifier":"INCLUDES"},
            "hair_color":{"value":"Blonde","modifier":"EQUALS"},
            "performers":{"value":{"items":[{"id":"7","label":"J"}],"excluded":[{"id":"8","label":"K"}]},"modifier":"INCLUDES"}}""",
        )
        assertEquals(
            obj(
                """{"gender":{"value_list":["FEMALE","TRANSGENDER_FEMALE"],"modifier":"INCLUDES"},
                "circumcised":{"value":["UNCUT"],"modifier":"INCLUDES"},
                "hair_color":{"value":"Blonde","modifier":"EQUALS"},
                "performers":{"value":["7"],"modifier":"INCLUDES","excludes":["8"]}}""",
            ),
            FilterMapper.sanitize(web, entity = FilterMapper.Entity.Performers),
        )
    }

    @Test fun studioParentsNeverCarryDepth() {
        val web = obj("""{"parents":{"value":{"items":[{"id":"3","label":"P"}],"excluded":[],"depth":2},"modifier":"INCLUDES"}}""")
        assertEquals(
            obj("""{"parents":{"value":["3"],"modifier":"INCLUDES"}}"""),
            FilterMapper.sanitize(web, entity = FilterMapper.Entity.Studios),
        )
        assertEquals(
            obj("""{"parents":{"value":["3"],"modifier":"INCLUDES","depth":2}}"""),
            FilterMapper.sanitize(web, entity = FilterMapper.Entity.Tags),
        )
        // Through the criteria document (the editor's load path) the mode decides.
        val f = SavedFilter("1", "S", "STUDIOS", objectFilter = obj("""{"parents":{"value":[{"id":"3","label":"P"}],"modifier":"INCLUDES"}}"""))
        assertEquals(obj("""{"parents":{"value":["3"],"modifier":"INCLUDES"}}"""), f.criteriaObjectFilter())
    }

    // MARK: - Load (older app saves)

    @Test fun loadsOldAppFormat() {
        val old = obj(
            """{"resolution":{"value":"QUAD_HD","modifier":"EQUALS"},
            "tags":{"value":[5,6],"modifier":"INCLUDES"},
            "performers":{"value":{"items":[{"id":7,"label":"J"}],"excluded":[]},"modifier":"INCLUDES"},
            "created_at":{"value":"2024-01-31T13:45","modifier":"GREATER_THAN"},
            "duplicated":{"duplicated":true},
            "stash_id_endpoint":{"stash_id":"abc","modifier":"EQUALS"},
            "organized":{"value":"true","modifier":"EQUALS"},
            "rating100":{"value":"60","modifier":"GREATER_THAN"}}""",
        )
        assertEquals(
            obj(
                """{"resolution":{"value":"QUAD_HD","modifier":"EQUALS"},
                "tags":{"value":["5","6"],"modifier":"INCLUDES","depth":0},
                "performers":{"value":["7"],"modifier":"INCLUDES"},
                "created_at":{"value":"2024-01-31T13:45","modifier":"GREATER_THAN"},
                "duplicated":{"duplicated":true},
                "stash_id_endpoint":{"modifier":"EQUALS","stash_id":"abc"},
                "organized":true,
                "rating100":{"value":60,"modifier":"GREATER_THAN"}}""",
            ),
            FilterMapper.sanitize(old, entity = FilterMapper.Entity.Scenes),
        )
        // Legacy single gender value → full value_list; no uppercasing of free-text fields.
        assertEquals(
            obj("""{"gender":{"value_list":["FEMALE"],"modifier":"INCLUDES"},"ethnicity":{"value":"Caucasian","modifier":"EQUALS"}}"""),
            FilterMapper.sanitize(
                obj("""{"gender":{"value":"FEMALE","modifier":"INCLUDES"},"ethnicity":{"value":"Caucasian","modifier":"EQUALS"}}"""),
                entity = FilterMapper.Entity.Performers,
            ),
        )
        // Web UI booleans of older Stash versions for `duplicated`.
        assertEquals(
            obj("""{"duplicated":{"phash":true}}"""),
            FilterMapper.sanitize(obj("""{"duplicated":{"value":"true","modifier":"EQUALS"}}"""), entity = FilterMapper.Entity.Scenes),
        )
    }

    @Test fun sanitizeIsIdempotentOnQueryFormat() {
        val once = FilterMapper.sanitize(obj(sceneQuery), entity = FilterMapper.Entity.Scenes)
        assertEquals(once, FilterMapper.sanitize(once, entity = FilterMapper.Entity.Scenes))
    }

    // MARK: - Round trip

    @Test fun queryToSavedToQueryRoundTrips() {
        fun roundTrip(query: JsonObject, entity: FilterMapper.Entity, variable: String) {
            val saved = FilterMapper.savedObjectFilter(query, entity, labels)
            // The saved filter travels as JSON text through the server.
            val reloaded = FilterMapper.sanitize(Json.parseToJsonElement(saved.toString()).jsonObject, entity = entity)
            val sent = FilterMapper.queryVariables(JsonObject(mapOf(variable to reloaded)))
            assertEquals(JsonObject(mapOf(variable to query)), sent)
        }
        roundTrip(obj(sceneQuery), FilterMapper.Entity.Scenes, "scene_filter")
        roundTrip(
            obj(
                """{"gender":{"value_list":["FEMALE","TRANSGENDER_FEMALE"],"modifier":"INCLUDES"},
                "circumcised":{"value":["CUT"],"modifier":"INCLUDES"},
                "filter_favorites":false,
                "birthdate":{"value":"1990-01-01","value2":"1995-01-01","modifier":"BETWEEN"},
                "tags":{"value":["5"],"modifier":"INCLUDES_ALL","depth":0},
                "stash_id_endpoint":{"modifier":"NOT_NULL"},
                "updated_at":{"value":"2024-02-01T00:00","value2":"2024-02-02T12:30","modifier":"NOT_BETWEEN"}}""",
            ),
            FilterMapper.Entity.Performers, "performer_filter",
        )
        roundTrip(
            obj("""{"parents":{"value":["3"],"modifier":"INCLUDES"},"favorite":true,"rating100":{"value":60,"modifier":"GREATER_THAN"}}"""),
            FilterMapper.Entity.Studios, "studio_filter",
        )
        roundTrip(
            obj("""{"parents":{"value":["2"],"modifier":"INCLUDES","depth":-1},"children":{"value":["9"],"excludes":["10"],"modifier":"INCLUDES","depth":0}}"""),
            FilterMapper.Entity.Tags, "tag_filter",
        )
        roundTrip(
            obj("""{"average_resolution":{"value":"FULL_HD","modifier":"GREATER_THAN"},"is_zip":true,"parent_folder":{"value":["4"],"modifier":"INCLUDES","depth":-1}}"""),
            FilterMapper.Entity.Galleries, "gallery_filter",
        )
    }

    // MARK: - Query time

    @Test fun folderMovesToFilesFilterOnlyInQueries() {
        val vars = obj(
            """{"filter":{"page":1},
            "scene_filter":{"folder":{"value":["8"],"modifier":"INCLUDES","depth":0},"files_filter":{"path":{"value":"x","modifier":"INCLUDES"}},
                "OR":{"folder":{"value":["9"],"modifier":"INCLUDES","depth":0}}},
            "object_filter":{"folder":{"value":["8"],"modifier":"INCLUDES"}}}""",
        )
        val out = FilterMapper.queryVariables(vars)
        val scene = out["scene_filter"]!!.jsonObject
        assertNull(scene["folder"])
        val files = scene["files_filter"]!!.jsonObject
        assertNotNull(files["path"])
        assertEquals(obj("""{"value":["8"],"modifier":"INCLUDES","depth":0}"""), files["parent_folder"])
        assertEquals(
            obj("""{"value":["9"],"modifier":"INCLUDES","depth":0}"""),
            scene["OR"]!!.jsonObject["files_filter"]!!.jsonObject["parent_folder"],
        )
        assertEquals(vars["object_filter"], out["object_filter"])
        // Nothing to move: the same object comes back.
        val plain = obj("""{"scene_filter":{"organized":true}}""")
        assertTrue(FilterMapper.queryVariables(plain) === plain)
    }

    // MARK: - Catalog / editor

    @Test fun timestampCriterionDefaultsAndFormat() {
        val d = CriterionKind.timestamp.defaultValue(FilterMode.Scenes) as JsonObject
        assertEquals(JsonPrimitive("GREATER_THAN"), d["modifier"])
        assertTrue(Regex("""^\d{4}-\d{2}-\d{2}T00:00$""").matches(d["value"].stringValue!!))
        assertEquals(
            listOf(CriterionModifier.GreaterThan, CriterionModifier.LessThan, CriterionModifier.Between, CriterionModifier.NotBetween),
            CriterionKind.timestamp.defaultModifiers,
        )
        assertEquals("2024-01-31T13:45", FilterTimestampFormat.parse("2024-01-31 13:45")?.let { FilterTimestampFormat.format(it) })
        assertEquals("2024-01-31T00:00", FilterTimestampFormat.parse("2024-01-31")?.let { FilterTimestampFormat.format(it) })
    }

    @Test fun catalogFieldsFollowWebUi() {
        val sceneAddable = FilterFieldCatalog.addableFields(FilterMode.Scenes, emptySet())
        // Sub-filters and files_filter are offered (marked "App only"); the Stash ID list is not.
        assertTrue(sceneAddable.any { it.kind == CriterionKind.nestedFilter })
        assertTrue(sceneAddable.any { it.key == "files_filter" })
        assertTrue(sceneAddable.none { it.kind == CriterionKind.stashIDs })
        assertEquals("Stash ID", sceneAddable.single { it.key == "stash_id_endpoint" }.label)
        // Loaded filters still show sub-filters and raw files filters.
        assertNotNull(FilterFieldCatalog.field("files_filter", FilterMode.Scenes))
        assertNull(FilterFieldCatalog.field("career_length", FilterMode.Performers))
        listOf(FilterMode.Performers, FilterMode.Studios, FilterMode.Tags).forEach { mode ->
            assertTrue("$mode", FilterFieldCatalog.addableFields(mode, emptySet()).any { it.key == "stash_id_endpoint" })
        }
        assertEquals(PickerKind.Studios, PickerKind.forCriterion("parents", FilterMode.Studios))
        assertEquals(PickerKind.AllTags, PickerKind.forCriterion("parents", FilterMode.Tags))
        assertEquals(PickerKind.Folders, PickerKind.forCriterion("folder", FilterMode.Scenes))
        assertEquals(PickerKind.Folders, PickerKind.forCriterion("parent_folder", FilterMode.Galleries))
        assertEquals(FilterMapper.LabelKind.Studio, PickerKind.ImageStudios.labelKind)
    }

    @Test fun folderFieldNeedsStash032() {
        // Unit tests run without a server version: an older (or unknown) server never sees Folder.
        assertFalse(ServerCapabilities.supports032)
        assertNull(FilterFieldCatalog.field("folder", FilterMode.Scenes))
        assertNull(FilterFieldCatalog.field("folder", FilterMode.Images))
        assertNull(FilterFieldCatalog.field("parent_folder", FilterMode.Galleries))
        assertNull(FilterFieldCatalog.field("production_date", FilterMode.Scenes))
    }
}
