/// The app's two regions (1.14.0 "Whole Moon"): the south pole, with its
/// detailed terrain and light map, and the rest of the Moon.
///
/// Rules (build plan §3):
/// - a preset's region is the catalogue it was loaded from; a custom spot's
///   region is the region it was made in;
/// - automatic choices (ranking, top pick, STANDS OUT, nearest site, rank
///   lines) never mix regions; only Compare may, by the user's choice;
/// - polar custom spots: lat ≤ −80.01 ([customLatAllowed], unchanged);
///   global custom spots: −80.01 < lat ≤ 80.0 ([globalCustomLatAllowed]).
///   A global tap at or south of −80.01 belongs to the south pole
///   ([regionForTapLat]): the app offers "Open in South-pole mode" and places
///   nothing. North of 80° N nothing is placed in this version (no
///   north-pole region).
library;

import 'dem.dart' show customLatAllowed, customMaxLatDeg;

/// Where the user is looking: the south-pole region (the default) or the
/// whole Moon outside it.
enum Region { southPole, wholeMoon }

/// The northern limit of global custom spots, degrees (planetocentric).
/// North of it lies the (not yet covered) north-pole region.
const double globalCustomMaxLatDeg = 80.0;

/// Whether a global ([Region.wholeMoon]) custom spot may be placed at
/// [latDeg]: −80.01 < lat ≤ 80.0, so the two regions' custom-spot ranges meet
/// without overlapping ([customLatAllowed] takes lat ≤ −80.01). NaN is refused.
bool globalCustomLatAllowed(double latDeg) => latDeg > customMaxLatDeg && latDeg <= globalCustomMaxLatDeg;

/// The region a tap (or typed coordinates) at [latDeg] belongs to: the south
/// pole at or south of −80.01 (where [customLatAllowed] holds), otherwise the
/// whole Moon. It says nothing about whether a spot may be placed there
/// (north of 80° N: see [globalCustomLatAllowed]).
Region regionForTapLat(double latDeg) => customLatAllowed(latDeg) ? Region.southPole : Region.wholeMoon;

/// The site selected on entering Whole Moon with no global site selected.
const String kGlobalDefaultSiteId = 'apollo-11-lm';
