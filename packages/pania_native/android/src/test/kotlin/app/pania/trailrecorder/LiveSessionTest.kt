package app.pania.trailrecorder

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveSessionTest {
    private val degreeM = 111_195.0
    private val t0 = 1_000_000_000L

    /** Latitude that is [meters] north of 46.0. */
    private fun north(meters: Double) = 46.0 + meters / degreeM

    private fun recording(info: String = """{"mode":"recording","title":"Recording trail"}"""): LiveSession =
        LiveSession().also { it.begin(info, null, t0) }

    private fun tour(lengthM: Double = 1_000.0, thresholdM: Int = 50): LiveSession {
        val guard = OffTrackGuard.parse(
            """{"thresholdM": $thresholdM, "track": [[46.0, 11.0], [${north(lengthM)}, 11.0]], "title": "Off"}""",
        )
        return LiveSession().also { it.begin("""{"mode":"tour","title":"Monte Pania"}""", guard, t0) }
    }

    @Test
    fun beginStartsEmptyWithTheGivenTitleAndLabels() {
        val s = LiveSession().begin("""{"mode":"recording","title":"Rec","labels":{"climb":"Salita"}}""", null, t0)
        assertEquals("recording", s.mode)
        assertEquals("Rec", s.title)
        assertEquals("Salita", s.label("climb", "Climb"))
        assertEquals("Distance", s.label("distance", "Distance"))
        assertEquals(0.0, s.distanceM, 0.0)
        assertEquals(t0, s.startedAtMs)
        assertEquals(-1, s.progressPct)
    }

    @Test
    fun aResumedRecordingCarriesOnFromItsBaseline() {
        val live = LiveSession()
        val s = live.begin("""{"mode":"recording","title":"Rec","baseDistanceM":1200,"baseAscentM":80,"baseElapsedMs":600000}""", null, t0)
        assertEquals(1200.0, s.distanceM, 0.0)
        assertEquals(80.0, s.ascentM, 0.0)
        assertEquals(t0 - 600_000, s.startedAtMs)
        val after = live.onFix(46.0, 11.0, null, 5f, t0, t0)
        assertEquals(1200.0, after.distanceM, 0.0)
    }

    @Test
    fun unusableJsonFallsBackToDefaults() {
        val s = LiveSession().begin("not json", null, t0)
        assertEquals("recording", s.mode)
        assertEquals("Pania", s.title)
    }

    @Test
    fun distanceAddsUpTheSteps() {
        val live = recording()
        live.onFix(north(0.0), 11.0, null, 5f, t0, t0)
        live.onFix(north(100.0), 11.0, null, 5f, t0 + 1_000, t0 + 1_000)
        val s = live.onFix(north(250.0), 11.0, null, 5f, t0 + 2_000, t0 + 2_000)
        assertEquals(250.0, s.distanceM, 1.0)
    }

    @Test
    fun jitterWhileStandingStillAddsNothing() {
        val live = recording()
        live.onFix(north(0.0), 11.0, null, 5f, t0, t0)
        var s = live.onFix(north(0.8), 11.0, null, 5f, t0 + 1_000, t0 + 1_000)
        s = live.onFix(north(1.5), 11.0, null, 5f, t0 + 2_000, t0 + 2_000)
        assertEquals(0.0, s.distanceM, 0.0)
        // The reference point stayed put, so a real step from it still counts in full.
        s = live.onFix(north(10.0), 11.0, null, 5f, t0 + 3_000, t0 + 3_000)
        assertEquals(10.0, s.distanceM, 0.5)
    }

    @Test
    fun aFixWithPoorAccuracyIsIgnoredForDistance() {
        val live = recording()
        live.onFix(north(0.0), 11.0, null, 5f, t0, t0)
        val s = live.onFix(north(500.0), 11.0, null, 80f, t0 + 1_000, t0 + 1_000)
        assertEquals(0.0, s.distanceM, 0.0)
    }

    @Test
    fun ascentIgnoresNoiseAndCountsRealClimbs() {
        val live = recording()
        var s = live.onFix(north(0.0), 11.0, 100.0, 5f, t0, t0)
        s = live.onFix(north(10.0), 11.0, 101.5, 5f, t0, t0)
        s = live.onFix(north(20.0), 11.0, 102.9, 5f, t0, t0)
        assertEquals(0.0, s.ascentM, 0.0)
        s = live.onFix(north(30.0), 11.0, 104.0, 5f, t0, t0)
        assertEquals(4.0, s.ascentM, 0.001)
        // Going down moves the reference down; climbing back up counts again.
        live.onFix(north(40.0), 11.0, 98.0, 5f, t0, t0)
        s = live.onFix(north(50.0), 11.0, 102.0, 5f, t0, t0)
        assertEquals(8.0, s.ascentM, 0.001)
    }

    @Test
    fun tourStartsAtZeroProgressWithTheWholeTrailLeft() {
        val g = OffTrackGuard.parse("""{"thresholdM": 50, "track": [[46.0, 11.0], [${north(1000.0)}, 11.0]]}""")
        val s = LiveSession().begin("""{"mode":"tour","title":"T"}""", g, t0)
        assertEquals("tour", s.mode)
        assertTrue(s.isTour)
        assertEquals(1000.0, s.remainingM, 1.0)
        assertEquals(0, s.progressPct)
        assertEquals(-1L, s.etaMs)
    }

    @Test
    fun tourTracksRemainingDistanceAndProgress() {
        val live = tour()
        val s = live.onFix(north(250.0), 11.0, null, 5f, t0, t0)
        assertEquals(750.0, s.remainingM, 2.0)
        assertEquals(25, s.progressPct)
        assertFalse(s.offTrack)
    }

    @Test
    fun tourReportsBeingOffTheTrail() {
        val live = tour()
        val east = 11.0 + 200.0 / (degreeM * Math.cos(Math.toRadians(46.0)))
        assertTrue(live.onFix(north(250.0), east, null, 5f, t0, t0).offTrack)
        assertFalse(live.onFix(north(260.0), 11.0, null, 5f, t0 + 3_000, t0 + 3_000).offTrack)
    }

    @Test
    fun arrivalTimeNeedsAMinuteOfWalking() {
        val live = tour()
        live.onFix(north(0.0), 11.0, null, 5f, t0, t0)
        val s = live.onFix(north(30.0), 11.0, null, 5f, t0 + 30_000, t0 + 30_000)
        assertEquals(-1L, s.etaMs)
    }

    @Test
    fun arrivalTimeComesFromTheRecentPace() {
        val live = tour(lengthM = 1_000.0)
        // One meter per second for two minutes.
        var s = live.onFix(north(0.0), 11.0, null, 5f, t0, t0)
        for (i in 1..12) {
            val time = t0 + i * 10_000L
            s = live.onFix(north(10.0 * i), 11.0, null, 5f, time, time)
        }
        val now = t0 + 120_000L
        // 120 m done, 880 m left at 1 m/s: 880 s from the last fix.
        assertTrue("eta was ${s.etaMs - now} ms from now", Math.abs(s.etaMs - (now + 880_000L)) < 2_000)
    }

    @Test
    fun standingStillGivesNoArrivalTime() {
        val live = tour()
        var s = live.onFix(north(100.0), 11.0, null, 5f, t0, t0)
        for (i in 1..10) s = live.onFix(north(100.0), 11.0, null, 5f, t0 + i * 10_000L, t0 + i * 10_000L)
        assertEquals(-1L, s.etaMs)
    }

    @Test
    fun snapshotSurvivesAJsonRoundTrip() {
        val live = recording("""{"mode":"recording","title":"Rec","labels":{"time":"Durata"}}""")
        val s = live.onFix(46.0, 11.0, 100.0, 5f, t0, t0)
        val back = LiveStats.Snapshot.fromJson(s.toJson())
        assertEquals(s.title, back.title)
        assertEquals(s.startedAtMs, back.startedAtMs)
        assertEquals("Durata", back.label("time", "Time"))
        assertEquals(s.updatedAtMs, back.updatedAtMs)
        assertEquals(JSONObject(s.toJson()).getString("mode"), back.mode)
    }
}
