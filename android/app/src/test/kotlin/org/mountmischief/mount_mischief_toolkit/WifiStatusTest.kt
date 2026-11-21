package org.mountmischief.mount_mischief_toolkit

import org.junit.Assert.*
import org.junit.Test

class WifiStatusTest {
    @Test fun associationMustBePresentAndNamed() {
        assertEquals("disconnected", WifiStatus.classify(false, "polaris_old")["state"])
        assertEquals("unknown", WifiStatus.classify(true, "<unknown ssid>")["state"])
        assertEquals("unknown", WifiStatus.classify(true, null)["state"])
        assertEquals("other", WifiStatus.classify(true, "Home")["state"])
        assertEquals("other", WifiStatus.classify(true, "not_polaris_123")["state"])
        assertEquals(mapOf("state" to "polaris", "ssid" to "polaris_123"), WifiStatus.classify(true, "\"polaris_123\""))
    }
}
