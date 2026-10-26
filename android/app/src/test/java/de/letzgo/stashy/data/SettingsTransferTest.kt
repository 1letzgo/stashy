package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsTransferTest {
    private fun setting(key: String, type: String, value: kotlinx.serialization.json.JsonElement) = SettingsTransferFile.Setting(key, type, value)

    @Test fun filterKeepsSettingsAndDropsSecretsStateAndServerLists() {
        assertTrue(SettingsTransfer.isTransferable("isPiPEnabled"))
        assertTrue(SettingsTransfer.isTransferable("HomeRowsConfig_FE189A7C"))
        assertTrue(SettingsTransfer.isTransferable("scene_watchlist_FE189A7C"))
        listOf(
            "stashy_server_config", "stashy_saved_servers", "stashy_saved_servers_backup", "stashy_saved_servers_unreadable",
            "stashy_plus_license_key", "stashy_plus_source", "totalTipsCount", "kBiometricsEnabled", "kAutoLockOnBackground",
            "app_passcode_v1", "kPasscodeFailedAttempts", "mini_player_last_ABC", "cachedStats", "app_update_last_check",
            "stashy_plus_debug_force_locked", "some_license_thing", "NSWindow", "downloads_notification_permission_asked",
        ).forEach { assertFalse(it, SettingsTransfer.isTransferable(it)) }
    }

    @Test fun exportTypesFollowTheStoredValue() {
        assertEquals("bool", SettingsTransfer.exportEntry("a", true)?.type)
        assertEquals(JsonPrimitive(3L), SettingsTransfer.exportEntry("a", 3)?.value)
        assertEquals("int", SettingsTransfer.exportEntry("a", 3)?.type)
        assertEquals("int", SettingsTransfer.exportEntry("a", 5_000_000_000L)?.type)
        val f = SettingsTransfer.exportEntry("a", 0.4f)!!
        assertEquals("double", f.type)
        assertEquals(JsonPrimitive(0.4), f.value)
        assertEquals("string", SettingsTransfer.exportEntry("a", "dark")?.type)
        val j = SettingsTransfer.exportEntry("a", """[{"id":"x","on":true}]""")!!
        assertEquals("json", j.type)
        assertTrue(j.value is JsonArray)
        assertEquals("string", SettingsTransfer.exportEntry("a", "[not json")?.type)
        val set = SettingsTransfer.exportEntry("a", setOf("b", "a"))!!
        assertEquals("array", set.type)
        assertEquals(JsonArray(listOf(JsonPrimitive("a"), JsonPrimitive("b"))), set.value)
        assertNull(SettingsTransfer.exportEntry("a", null))
    }

    @Test fun importWithoutExistingKeyUsesTheFileType() {
        assertEquals(StoredPref.BoolValue(true), SettingsTransfer.resolveImport(setting("k", "bool", JsonPrimitive(true)), null))
        assertEquals(StoredPref.IntValue(10), SettingsTransfer.resolveImport(setting("k", "int", JsonPrimitive(10)), null))
        assertEquals(StoredPref.LongValue(5_000_000_000L), SettingsTransfer.resolveImport(setting("k", "int", JsonPrimitive(5_000_000_000L)), null))
        assertEquals(StoredPref.FloatValue(10f), SettingsTransfer.resolveImport(setting("k", "double", JsonPrimitive(10)), null))
        assertEquals(StoredPref.StringValue("dark"), SettingsTransfer.resolveImport(setting("k", "string", JsonPrimitive("dark")), null))
        assertEquals(StoredPref.StringValue("""[{"a":1}]"""), SettingsTransfer.resolveImport(setting("k", "json", JsonArray(listOf(JsonObject(mapOf("a" to JsonPrimitive(1)))))), null))
        assertEquals(StoredPref.StringValue("""{"x":"y"}"""), SettingsTransfer.resolveImport(setting("k", "dictionary", JsonObject(mapOf("x" to JsonPrimitive("y")))), null))
        assertNull(SettingsTransfer.resolveImport(setting("k", "date", JsonPrimitive("2026")), null))
        assertNull(SettingsTransfer.resolveImport(setting("k", "bool", JsonPrimitive("yes")), null))
    }

    @Test fun importKeepsTheLocalTypeOfAnExistingKey() {
        assertEquals(StoredPref.FloatValue(10f), SettingsTransfer.resolveImport(setting("k", "int", JsonPrimitive(10)), 5f))
        assertEquals(StoredPref.IntValue(3), SettingsTransfer.resolveImport(setting("k", "double", JsonPrimitive(3.0)), 1))
        assertEquals(StoredPref.LongValue(7L), SettingsTransfer.resolveImport(setting("k", "int", JsonPrimitive(7)), 1L))
        assertEquals(StoredPref.StringValue("30"), SettingsTransfer.resolveImport(setting("k", "int", JsonPrimitive(30)), "10"))
        assertEquals(StoredPref.StringValue("true"), SettingsTransfer.resolveImport(setting("k", "bool", JsonPrimitive(true)), "false"))
        assertEquals(StoredPref.BoolValue(true), SettingsTransfer.resolveImport(setting("k", "string", JsonPrimitive("true")), false))
        assertEquals(StoredPref.StringSetValue(setOf("FEMALE", "MALE")), SettingsTransfer.resolveImport(setting("k", "array", JsonArray(listOf(JsonPrimitive("FEMALE"), JsonPrimitive("MALE")))), setOf("X")))
    }

    @Test fun rejectsOtherFilesAndNewerVersions() {
        assertThrows { SettingsTransfer.parse("""{"format":"something","version":1}""") }
        assertThrows { SettingsTransfer.parse("""{"format":"stashy-settings","version":2}""") }
        assertThrows { SettingsTransfer.parse("not json") }
    }

    @Test fun parsesAnIosFileAndMapsEveryEntry() {
        val file = SettingsTransfer.parse(IOS_SAMPLE)
        assertEquals("ios", file.app.platform)
        assertTrue(file.includesSecrets)
        assertEquals("FE189A7C-F11D-435E-979F-AC8CB93B11A5", file.activeServerId)

        val server = SettingsTransfer.serverConfig(file.servers.single())!!
        assertEquals("FE189A7C-F11D-435E-979F-AC8CB93B11A5", server.id)
        assertEquals(ServerProtocol.HTTP, server.serverProtocol)
        assertEquals("9999", server.port)
        assertNull(server.subpath)
        assertEquals("http://192.168.1.10:9999", server.baseURL)
        assertEquals("secret-key", file.servers.single().apiKey)
        assertEquals("X-Token", file.servers.single().customHeaders?.single()?.name)

        val stored = file.settings.associate { it.key to SettingsTransfer.resolveImport(it, null) }
        assertEquals(StoredPref.BoolValue(true), stored["isPiPEnabled"])
        assertEquals(StoredPref.IntValue(25), stored["download_batch_size"])
        assertEquals(StoredPref.FloatValue(0.5f), stored["kGlassTransparency"])
        assertEquals(StoredPref.StringValue("dark"), stored["kPreferredTheme"])
        assertEquals(StoredPref.StringValue("""[{"id":"recent","isEnabled":true}]"""), stored["HomeRowsConfig_FE189A7C-F11D-435E-979F-AC8CB93B11A5"])
        assertEquals(StoredPref.StringValue("""["FEMALE"]"""), stored["stashy.hotOrNot.selectedGenders"])
        assertNull(stored["someDate"])
    }

    @Test fun exportedFileRoundTrips() {
        val server = SettingsTransferFile.Server("ID-1", "Home", "stash.local", "9999", "HTTP")
        val file = SettingsTransfer.buildFile(
            mapOf("isPiPEnabled" to true, "kGlassTransparency" to 0.5f, "stashy_plus_source" to "license", "HomeRowsConfig_ID-1" to """[1,2]"""),
            listOf(server), "ID-1", includeSecrets = false, exportedAt = "2026-10-24T18:00:00Z", version = "1.0", build = "1",
        )
        assertEquals(listOf("HomeRowsConfig_ID-1", "isPiPEnabled", "kGlassTransparency"), file.settings.map { it.key })
        val text = SettingsTransfer.json.encodeToString(SettingsTransferFile.serializer(), file)
        assertFalse("secrets are omitted", "apiKey" in text)
        val back = SettingsTransfer.parse(text)
        assertEquals("android", back.app.platform)
        assertEquals(file.settings, back.settings)
        assertEquals(server, back.servers.single())
    }

    private fun assertThrows(block: () -> Unit) {
        val failed = runCatching(block).isFailure
        assertTrue("expected an exception", failed)
    }

    companion object {
        private val IOS_SAMPLE = """
        {
          "activeServerId" : "FE189A7C-F11D-435E-979F-AC8CB93B11A5",
          "app" : { "build" : "410", "platform" : "ios", "version" : "3.3.7" },
          "exportedAt" : "2026-10-24T18:00:00Z",
          "format" : "stashy-settings",
          "includesSecrets" : true,
          "servers" : [
            {
              "apiKey" : "secret-key",
              "customHeaders" : [ { "id" : "8A1F2C3D-0000-0000-0000-000000000001", "name" : "X-Token", "value" : "abc" } ],
              "id" : "FE189A7C-F11D-435E-979F-AC8CB93B11A5",
              "name" : "My Stash",
              "port" : "9999",
              "serverAddress" : "192.168.1.10",
              "serverProtocol" : "HTTP"
            }
          ],
          "settings" : [
            { "key" : "HomeRowsConfig_FE189A7C-F11D-435E-979F-AC8CB93B11A5", "type" : "json", "value" : [ { "id" : "recent", "isEnabled" : true } ] },
            { "key" : "download_batch_size", "type" : "int", "value" : 25 },
            { "key" : "isPiPEnabled", "type" : "bool", "value" : true },
            { "key" : "kGlassTransparency", "type" : "double", "value" : 0.5 },
            { "key" : "kPreferredTheme", "type" : "string", "value" : "dark" },
            { "key" : "someDate", "type" : "date", "value" : "2026-01-01" },
            { "key" : "stashy.hotOrNot.selectedGenders", "type" : "array", "value" : [ "FEMALE" ] }
          ],
          "version" : 1
        }
        """.trimIndent()
    }
}
