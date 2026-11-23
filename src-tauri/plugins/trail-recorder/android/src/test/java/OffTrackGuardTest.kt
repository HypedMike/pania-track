package app.pania.trailrecorder

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OffTrackGuardTest {
    /** One degree of latitude in meters, as the guard assumes. */
    private val degreeM = 111_195.0

    /** A straight trail going north from (46, 11), 0.01° (about 1112 m) long, with a middle point. */
    private fun guard(thresholdM: Int = 50): OffTrackGuard = OffTrackGuard.parse(
        """{"thresholdM": $thresholdM, "track": [[46.0, 11.0], [46.005, 11.0], [46.01, 11.0]],
            "title": "Off", "text": "{m} m away"}""",
    )

    /** A longitude offset that is [meters] east of the trail at latitude 46. */
    private fun eastOf(meters: Double) = 11.0 + meters / (degreeM * Math.cos(Math.toRadians(46.0)))

    @Test
    fun totalLengthIsTheSumOfTheSegments() {
        assertEquals(0.01 * degreeM, guard().totalLengthM, 1.0)
    }

    @Test
    fun projectGivesDistanceFromAndPositionAlongTheTrail() {
        val (off, along) = guard().project(46.005, 11.0)
        assertEquals(0.0, off, 0.5)
        assertEquals(0.005 * degreeM, along, 1.0)
    }

    @Test
    fun projectMeasuresSidewaysDistance() {
        val (off, along) = guard().project(46.0025, eastOf(100.0))
        assertEquals(100.0, off, 1.0)
        assertEquals(0.0025 * degreeM, along, 1.0)
    }

    @Test
    fun beyondTheEndsClampsToTheEndpoints() {
        val (_, before) = guard().project(45.99, 11.0)
        val (_, after) = guard().project(46.02, 11.0)
        assertEquals(0.0, before, 0.5)
        assertEquals(guard().totalLengthM, after, 0.5)
    }

    @Test
    fun distanceToTrailMatchesProject() {
        val g = guard()
        assertEquals(g.project(46.003, eastOf(30.0)).first, g.distanceToTrail(46.003, eastOf(30.0)), 0.0001)
    }

    @Test
    fun aSingleStrayFixDoesNotAlert() {
        val g = guard()
        assertEquals(OffTrackGuard.Verdict.NONE, g.onFix(46.005, eastOf(200.0), 5f, 0).first)
    }

    @Test
    fun twoFixesInARowBeyondTheThresholdAlertOnce() {
        val g = guard()
        g.onFix(46.005, eastOf(200.0), 5f, 0)
        assertEquals(OffTrackGuard.Verdict.OFF_TRACK, g.onFix(46.005, eastOf(200.0), 5f, 3_000).first)
        assertEquals(OffTrackGuard.Verdict.NONE, g.onFix(46.005, eastOf(200.0), 5f, 6_000).first)
    }

    @Test
    fun remindsAfterTwoMinutesWhileStillOff() {
        val g = guard()
        g.onFix(46.005, eastOf(200.0), 5f, 0)
        g.onFix(46.005, eastOf(200.0), 5f, 3_000)
        assertEquals(OffTrackGuard.Verdict.STILL_OFF_TRACK, g.onFix(46.005, eastOf(200.0), 5f, 130_000).first)
    }

    @Test
    fun comingBackClearsTheAlertOnlyWellInsideTheThreshold() {
        val g = guard()
        g.onFix(46.005, eastOf(200.0), 5f, 0)
        g.onFix(46.005, eastOf(200.0), 5f, 3_000)
        // 45 m is inside 50 m but not inside 70% of it (35 m): still counts as off.
        assertEquals(OffTrackGuard.Verdict.NONE, g.onFix(46.005, eastOf(45.0), 5f, 6_000).first)
        assertEquals(OffTrackGuard.Verdict.BACK_ON_TRACK, g.onFix(46.005, eastOf(10.0), 5f, 9_000).first)
    }

    @Test
    fun aFixLessAccurateThanTheThresholdSaysNothing() {
        val g = guard()
        g.onFix(46.005, eastOf(200.0), 5f, 0)
        assertEquals(OffTrackGuard.Verdict.NONE, g.onFix(46.005, eastOf(200.0), 120f, 3_000).first)
        // It did not count as the second fix either.
        assertEquals(OffTrackGuard.Verdict.OFF_TRACK, g.onFix(46.005, eastOf(200.0), 5f, 6_000).first)
    }

    @Test
    fun textRoundsTheDistanceToFiveMeters() {
        assertEquals("50 m away", guard().text(52.0))
        assertEquals("55 m away", guard().text(53.0))
        assertEquals("Off", guard().title)
    }

    @Test
    fun anEmptyTrailIsRejected() {
        val bad = runCatching { OffTrackGuard.parse("""{"thresholdM": 50, "track": []}""") }
        assertTrue(bad.isFailure)
    }
}
