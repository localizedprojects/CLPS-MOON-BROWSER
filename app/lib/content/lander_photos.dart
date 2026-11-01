/// "Real photos from this lander" (user decision 2026-11-01): for the two
/// landed NASA-CLPS landers, links to their real photos on NASA's own pages.
///
/// Nothing here is downloaded or bundled. The surface photos are copyright
/// Intuitive Machines, and NASA's media guidelines say NASA's use of
/// third-party copyrighted material "does not convey any rights to others", so
/// the app only names the page and shows its address (selectable, like the
/// other sources: the Android app has no internet permission and no URL
/// launcher). The orbital photos are NASA/Goddard/Arizona State University.
///
/// Every page was fetched live on 2026-11-01 (each answered 200) and its title,
/// date and credit checked against it. Titles are the pages' own, NASA's
/// spelling kept. Exceptions and notes:
/// - "Odysseus Lands on the Moon" shows no credit line, and its caption says the
///   photo was "retrieved on Feb. 27". The credit and the "taken" date come from
///   NASA's 28 Feb 2024 Artemis blog caption of the same narrow-field photo:
///   "Taken on Tuesday, Feb. 27, Odysseus captured an image using its
///   narrow-field-of-view camera. Credit: Intuitive Machines".
/// - Athena's surface photo: the caption puts it "about 820 feet" (250 m) from
///   the intended site; the same NASA release also says IM-2 touched down "more
///   than 1,300 feet (400 meters)" from it. The card keeps the caption's figure.
/// - Athena from orbit: NASA's caption places it "near the center of Mons
///   Mouton", but this app's site notes (sites.json) put the landed point about
///   20.5 km from the Mons Mouton (Leibnitz Beta Plateau) centre, in a region
///   LROC does not name, so the card leaves the location out.
/// Dropped: NASA's PRIME-1 mission page, whose pictures are artist's renderings
/// and lab photos, not photos from the Moon. Dropped: NASA's 28 Feb 2024
/// Artemis blog post, whose image blocks are empty on the live page (captions
/// only); its landing-leg photo is on the APOD page.
library;

/// One page on NASA's site that shows a real photo from (or of) a lander.
class LanderPhotoLink {
  /// The page's own title.
  final String title;

  /// One plain sentence: what the photo shows.
  final String shows;

  /// When the photo was taken (or, only when no NASA page says, posted),
  /// worded for the card: 'Taken 27 Feb 2024'. The day is NASA's own calendar
  /// date as its page gives it: NASA gives no UTC time, so it is not converted.
  final String date;

  /// Who holds the photo, as NASA credits it (see the library notes).
  final String credit;

  final String url;

  /// Taken from orbit (NASA's Lunar Reconnaissance Orbiter), not by the lander.
  final bool fromOrbit;

  const LanderPhotoLink({
    required this.title,
    required this.shows,
    required this.date,
    required this.credit,
    required this.url,
    this.fromOrbit = false,
  });
}

/// A lander's links and the one fact a reader needs before opening them.
class LanderPhotos {
  final String fact;
  final List<LanderPhotoLink> links;
  const LanderPhotos({required this.fact, required this.links});

  List<LanderPhotoLink> get surface => [for (final l in links) if (!l.fromOrbit) l];
  List<LanderPhotoLink> get orbit => [for (final l in links) if (l.fromOrbit) l];
}

const landerPhotosTitle = 'Real photos from this lander';
const landerPhotosNote =
    'Photos © Intuitive Machines, shown on NASA\'s pages; opened by link, not included in the app.';
const landerPhotosSurfaceHeading = 'From the lander';
const landerPhotosOrbitHeading = 'From orbit';

/// 'Credit: Intuitive Machines'.
String landerPhotoCredit(LanderPhotoLink l) => 'Credit: ${l.credit}';

/// What a screen reader hears on a link's selectable address.
String landerPhotoUrlSemantics(LanderPhotoLink l) => 'Web address of ${l.title}, on NASA\'s site';

const _im = 'Intuitive Machines';
const _lro = 'NASA/Goddard/Arizona State University';

/// The links, by site id (only the two landed landers).
const landerPhotos = <String, LanderPhotos>{
  'im-1-odysseus-landed': LanderPhotos(
    fact: 'Odysseus came to rest tilted about 30° on a 12° slope, so its photos\' horizons are not level.',
    links: [
      LanderPhotoLink(
        title: 'Odysseus Lands on the Moon',
        shows: 'A photo from the lander\'s narrow-field camera, with lander hardware in front and a crater beyond.',
        date: 'Taken 27 Feb 2024',
        credit: _im,
        url: 'https://www.nasa.gov/image-article/odysseus-lands-on-the-moon/',
      ),
      LanderPhotoLink(
        title: 'APOD: 2024 March 2 - Odysseus on the Moon',
        shows: 'A landing leg touching the surface while the engine still fires, at touchdown.',
        date: 'Taken 22 Feb 2024',
        credit: _im,
        url: 'https://science.nasa.gov/image-article/apod-2024-march-2-odysseus-on-the-moon/',
      ),
      LanderPhotoLink(
        title: 'NASA\'s LRO Images Intuitive Machine\'s Odysseus Lander',
        shows: 'The Lunar Reconnaissance Orbiter\'s camera photo of the lander on the ground.',
        date: 'Taken 24 Feb 2024',
        credit: _lro,
        url: 'https://www.nasa.gov/missions/lro/nasas-lro-images-intuitive-machines-odysseus-lander/',
        fromOrbit: true,
      ),
    ],
  ),
  'im-2-athena-landed': LanderPhotos(
    fact: 'Athena landed on its side in a small crater, so its photos are tilted.',
    links: [
      LanderPhotoLink(
        title: 'NASA Receives Some Data Before Intuitive Machines Ends Lunar Mission',
        shows: 'A surface photo showing Athena on its side, about 250 m (820 ft) from its intended site on Mons Mouton.',
        date: 'Taken 6 Mar 2025',
        credit: _im,
        url: 'https://www.nasa.gov/news-release/nasa-receives-some-data-before-intuitive-machines-ends-lunar-mission/',
      ),
      LanderPhotoLink(
        title: 'NASA\'s Lunar Reconnaissance Orbiter Views IM-2 on Moon\'s Surface',
        shows: 'The Lunar Reconnaissance Orbiter\'s camera photo of Athena on the ground, the day after landing.',
        date: 'Taken 7 Mar 2025',
        credit: _lro,
        url: 'https://www.nasa.gov/image-article/nasas-lunar-reconnaissance-orbiter-views-im-2-on-moons-surface/',
        fromOrbit: true,
      ),
    ],
  ),
};
