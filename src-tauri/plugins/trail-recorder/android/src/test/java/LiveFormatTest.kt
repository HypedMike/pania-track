package app.pania.trailrecorder

import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import java.util.Locale

class LiveFormatTest {
    @Before
    fun fixLocale() = Locale.setDefault(Locale.US)

    @Test
    fun shortDistancesAreInMeters() {
        assertEquals("0 m", LiveFormat.distance(0.0))
        assertEquals("999 m", LiveFormat.distance(999.4))
    }

    @Test
    fun longDistancesAreInKilometers() {
        assertEquals("1.0 km", LiveFormat.distance(1000.0))
        assertEquals("12.3 km", LiveFormat.distance(12_340.0))
    }

    @Test
    fun climbIsRoundedMeters() {
        assertEquals("43 m", LiveFormat.climb(42.6))
    }
}
