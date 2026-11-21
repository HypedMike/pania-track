import btools.mapcreator.*;
import btools.router.*;
import java.io.*;
import java.util.*;

/** Spike: build BRouter segments from test OSM data and compare steepness variants. */
public class Spike {
  public static void main(String[] a) throws Exception {
    System.setProperty("avoidMapPolling", "true");
    switch (a[0]) {
      case "exaggerate": exaggerate(a[1], a[2], Double.parseDouble(a[3]), Integer.parseInt(a[4])); break;
      case "build": build(new File(a[1]), new File(a[2]), new File(a[3]), new File(a[4])); break;
      case "route": route(new File(a[1]), new File(a[2]), a[3]); break;
      default: throw new IllegalArgumentException(a[0]);
    }
  }

  /** Scales elevation differences around the raster's minimum by `factor`. */
  static void exaggerate(String in, String out, double factor, int min) throws Exception {
    ElevationRasterCoder c = new ElevationRasterCoder();
    ElevationRaster r = c.decodeRaster(new BufferedInputStream(new FileInputStream(in)));
    for (int i = 0; i < r.eval_array.length; i++) {
      short s = r.eval_array[i];
      if (s != r.noDataValue) r.eval_array[i] = (short) Math.round(min + (s - min) * factor);
    }
    try (OutputStream os = new BufferedOutputStream(new FileOutputStream(out))) { c.encodeRaster(r, os); }
  }

  /** Same pipeline as BRouter's MapcreatorTest. */
  static void build(File pbf, File srtmDir, File profileDir, File tmp) throws Exception {
    tmp.mkdirs();
    File nodes = mk(tmp, "nodetiles"), ways = mk(tmp, "waytiles"), nodes55 = mk(tmp, "nodes55"), ways55 = mk(tmp, "waytiles55");
    File lookup = new File(profileDir, "lookups.dat"), rel = new File(tmp, "cycleways.dat"), res = new File(tmp, "restrictions.dat");
    File border = new File(tmp, "bordernids.dat");
    OsmFastCutter.doCut(lookup, nodes, ways, nodes55, ways55, border, rel, res,
      new File(profileDir, "all.brf"), new File(profileDir, "trekking.brf"), new File(profileDir, "softaccess.brf"), pbf, null);
    File unodes55 = mk(tmp, "unodes55"), bordernodes = new File(tmp, "bordernodes.dat");
    new PosUnifier().process(nodes55, unodes55, border, bordernodes, srtmDir.getAbsolutePath(), null);
    new WayLinker().process(unodes55, ways55, bordernodes, res, lookup, new File(profileDir, "all.brf"), mk(tmp, "segments"), "rd5");
  }

  static File mk(File p, String n) { File f = new File(p, n); f.mkdirs(); return f; }

  static final double[][] PAIRS = { // {fromLon, fromLat, toLon, toLat}
    {8.7030, 49.9950, 8.7240, 50.0085},
    {8.7030, 50.0085, 8.7240, 49.9950},
    {8.7020, 50.0020, 8.7245, 50.0010},
  };

  static final String[][] VARIANTS = { // name, consider_elevation, uphillcost, downhillcost, cutoff(%)
    {"direct",   "0", "7",  "7",  "3"},
    {"balanced", "1",  "7",  "7",  "3"},
    {"gentle",   "1",  "40", "30", "1"},
  };

  static void route(File segDir, File profile, String label) throws Exception {
    System.out.println("### " + label);
    System.out.printf("%-6s %-9s %8s %7s %8s %9s %8s%n", "route", "variant", "dist_m", "gain_m", "maxUp%", "maxDown%", "ms");
    for (int p = 0; p < PAIRS.length; p++) {
      for (String[] v : VARIANTS) {
        RoutingContext rc = new RoutingContext();
        rc.localFunction = profile.getAbsolutePath();
        rc.keyValues = new HashMap<>();
        rc.keyValues.put("consider_elevation", v[1]);
        rc.keyValues.put("uphillcostvalue", v[2]);
        rc.keyValues.put("downhillcostvalue", v[3]);
        rc.keyValues.put("uphillcutoffvalue", v[4]);
        rc.keyValues.put("downhillcutoffvalue", v[4]);
        List<OsmNodeNamed> wp = new ArrayList<>();
        wp.add(node("from", PAIRS[p][0], PAIRS[p][1]));
        wp.add(node("to", PAIRS[p][2], PAIRS[p][3]));
        String base = new File(segDir.getParentFile(), "out_" + label + "_" + p + "_" + v[0]).getAbsolutePath();
        RoutingEngine re = new RoutingEngine(null, null, segDir, wp, rc);
        long t0 = System.currentTimeMillis();
        re.doRun(0);
        long ms = System.currentTimeMillis() - t0;
        if (re.getErrorMessage() != null) { System.out.println(p + " " + v[0] + " ERROR " + re.getErrorMessage()); continue; }
        OsmTrack t = re.getFoundTrack();
        double[] s = stats(t.nodes);
        System.out.printf("%-6d %-9s %8.0f %7.0f %8.1f %9.1f %8d%n", p, v[0], s[0], s[1], s[2], s[3], ms);
        writeGeoJson(t.nodes, base + ".geojson");
      }
    }
  }

  static OsmNodeNamed node(String name, double lon, double lat) {
    OsmNodeNamed n = new OsmNodeNamed();
    n.name = name;
    n.ilon = 180000000 + (int) (lon * 1000000 + 0.5);
    n.ilat = 90000000 + (int) (lat * 1000000 + 0.5);
    return n;
  }

  static double lon(OsmPathElement e) { return (e.getILon() - 180000000) / 1e6; }
  static double lat(OsmPathElement e) { return (e.getILat() - 90000000) / 1e6; }

  static double hav(double lo1, double la1, double lo2, double la2) {
    double r = Math.PI / 180, dLa = (la2 - la1) * r, dLo = (lo2 - lo1) * r;
    double h = Math.pow(Math.sin(dLa / 2), 2) + Math.cos(la1 * r) * Math.cos(la2 * r) * Math.pow(Math.sin(dLo / 2), 2);
    return 2 * 6371000 * Math.asin(Math.sqrt(h));
  }

  /** {distance, elevation gain, max uphill grade %, max downhill grade %}; grades over >= 50 m windows. */
  static double[] stats(List<OsmPathElement> all) {
    List<OsmPathElement> n = all;
    int k = n.size();
    // 5-point median filter: removes isolated elevation spikes (e.g. at snapped start/end points)
    double[] el = new double[k];
    for (int i = 0; i < k; i++) {
      double[] w = new double[Math.min(k, i + 3) - Math.max(0, i - 2)];
      for (int j = Math.max(0, i - 2); j < Math.min(k, i + 3); j++) w[j - Math.max(0, i - 2)] = n.get(j).getElev();
      Arrays.sort(w); el[i] = w[w.length / 2];
    }
    double[] cum = new double[k];
    for (int i = 1; i < k; i++) cum[i] = cum[i - 1] + hav(lon(n.get(i - 1)), lat(n.get(i - 1)), lon(n.get(i)), lat(n.get(i)));
    double gain = 0, ref = el[0];
    for (double e : el) { if (e - ref >= 3) { gain += e - ref; ref = e; } else if (ref - e >= 3) ref = e; }
    double up = 0, down = 0;
    for (int i = 0, j = 0; i < k; i++) {
      while (j < k && cum[j] - cum[i] < 50) j++;
      if (j >= k) break;
      double g = (el[j] - el[i]) / (cum[j] - cum[i]) * 100;
      up = Math.max(up, g); down = Math.max(down, -g);
    }
    return new double[] {cum[k - 1], gain, up, down};
  }

  static void writeGeoJson(List<OsmPathElement> n, String f) throws IOException {
    StringBuilder sb = new StringBuilder("{\"type\":\"LineString\",\"coordinates\":[");
    for (int i = 0; i < n.size(); i++) {
      if (i > 0) sb.append(',');
      sb.append('[').append(lon(n.get(i))).append(',').append(lat(n.get(i))).append(',').append(n.get(i).getElev()).append(']');
    }
    try (Writer w = new FileWriter(f)) { w.write(sb.append("]}").toString()); }
  }
}
