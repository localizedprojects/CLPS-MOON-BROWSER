/// The feature guides (user request 2026-10-20): for each screen, its major
/// controls in the order they appear, top to bottom, and what to say about
/// each. A step names a GuideTarget id (widgets/feature_guide.dart); one
/// whose control is not on screen (another layout, or not there yet) is left
/// out, and shows in a short guide of its own once it is there (Compare's
/// results after sites are picked).
library;

/// One step: the control [target] and what it does.
class GuideStep {
  final String target, title, body;
  const GuideStep(this.target, this.title, this.body);
}

/// The steps of each guide, by guide id (see `guideIdFor`).
const guideSteps = <String, List<GuideStep>>{
  'explore': [
    GuideStep('pill', 'Mission settings',
        'Your dates and lander height. Tap to change the period, a 2 m lander or a 10 m mast, and the Sun, Earth and DSN rules.'),
    GuideStep('map', 'The south-pole map',
        'Every landing site at its real place on NASA terrain. Tap a marker to open a site, or tap anywhere south of 80°S to test your own spot.'),
    GuideStep('map-layers', 'Map layers', 'Change what the map shows, such as average sunlight or where Earth is in view.'),
    GuideStep('top-pick', 'Your best spot',
        'The top site for your dates and goal, and how long the Sun and Earth are up together there. See this site opens it; Compare top 3 starts a comparison.'),
    GuideStep('goal-chips', 'What matters most?',
        'Re-rank every site for a balance, for solar power or for Earth contact. The app remembers your choice.'),
    GuideStep('nav', 'Four places to go',
        'Explore, Site, Compare and Learn. Each one shows you around like this the first time you open it.'),
  ],
  'site.overview': [
    GuideStep('change-site', 'Change site', 'Pick another site, or one of your own spots. It opens on the same tab.'),
    GuideStep('site-tabs', 'Three views of a site', 'Overview, Sky & time and Light & shadow. Tap one, or swipe sideways.'),
    GuideStep('mission-length', 'How long you stay', 'Choose how many days the surface mission lasts.'),
    GuideStep('landing-find', 'Find the best landing window',
        'Finds the earliest landing whose whole mission keeps the Sun and Earth above the skyline.'),
    GuideStep('site-glance', 'At a glance',
        'What this place is, why it is on the list, what to watch out for and how it ranks. Catalogue sites are '
        'written from published sources; your own spots are described by the app from its numbers.'),
    GuideStep('site-more', 'More about this site',
        'The good-days calendar, the longest night to plan for, and the site\'s long-term record.'),
  ],
  'site.sky': [
    GuideStep('chart-sky', 'The sky plot',
        'The real terrain skyline around the site, with the Sun\'s and Earth\'s paths over your dates. Tap it to see it full screen.'),
    GuideStep('chart-timeline', 'The timeline',
        'How high the Sun and Earth are over the period, against the skyline under each. Tap it to see it full screen.'),
    GuideStep('time-bar', 'Play and the time bar',
        'Play through the period, step a day at a time, or drag to any moment. Tap the date and time to pick an exact '
        'moment (UTC). Light & shadow follows the same time.'),
    GuideStep('time-next', 'Next good stretch', 'Jumps to the next time the Sun and Earth are up together.'),
    GuideStep('simple-view', 'Simple view', 'Answers in plain words instead of the full charts.'),
  ],
  'site.light': [
    GuideStep('light-view', 'Close-up or whole region', 'A close-up around the site, or the whole region inside 80°S.'),
    GuideStep('light-layer', 'What is lit', 'Show where sunlight reaches, where Earth is in view, or both.'),
    GuideStep('light-map', 'Light and shadow',
        'Worked out on this device from NASA terrain, for the moment on the time bar.'),
    GuideStep('light-lander', 'Stand on the lander', 'See the horizon from 2 m up. Drag to look around; the light is the map\'s own.'),
    GuideStep('time-play', 'Watch the shadows move', 'Play moves ten hours per step here, so the shadows sweep at a readable pace.'),
  ],
  'compare': [
    GuideStep('compare-pick', 'Pick sites to compare', 'Start with the top 3, or add sites from Explore or a Site page.'),
    GuideStep('compare-winner', 'Best for your priorities',
        'The winning site and its score out of 100. Why this score? shows the arithmetic.'),
    GuideStep('chart-compare', 'Side by side', 'Each site\'s score, sunlight, Earth in view and longest dark, together.'),
    GuideStep('compare-add', 'Your shortlist', 'Add or remove sites: compare two to four at a time.'),
    GuideStep('compare-tune', 'Fine-tune', 'Set your own balance between power and communication.'),
  ],
  'learn': [
    GuideStep('share', 'Share & export', 'Save the numbers as CSV files, or the charts as pictures.'),
    GuideStep('validation', 'Validation & assumptions', 'How the numbers were checked against JPL Horizons and NASA\'s maps.'),
    GuideStep('learn-explain', 'Explain as I go', 'Adds a short explanation next to each chart and map.'),
    GuideStep('learn-guides', 'Show the guides again', 'Walk through every screen\'s guide once more.'),
  ],
};
