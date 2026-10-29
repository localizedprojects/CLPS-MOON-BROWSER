# Bundled data (`lunarhorizon/_bundled/`)

These files make the default **app mode** work offline, with the same numbers as the
Lunar Horizon app. They are byte-identical copies of the app's `app/assets/data/` files
(checked by `tests/test_bundled_matches_app.py` when the repository is present). Total
7.4 MB. Nothing here is hand-edited; the app's pipeline (`pipeline/lunarsp`)
generates them.

| What | Files | Made from |
|---|---|---|
| Compact ephemeris | `ephem/manifest.json`, `ephem/2025.bin` .. `2035.bin` | NAIF SPICE: DE440 (`de440s.bsp`), `moon_pa_de440_200625.bpc`, `moon_de440_250416.tf`, `naif0012.tls`. Hourly float32 Moon-centred apparent (`LT+S`) Sun and Earth vectors in `MOON_ME`, km, 2025-01-01T00:00Z .. 2035-12-31T23:00Z. Read by `CompactEphemeris` with 4-point Lagrange interpolation. |
| DSN bits | `dsn/2025.bin` .. `2035.bin` | SPICE with `earth_1962_260806_2126_combined.bpc` (ITRF93). One byte per hour: bit 0 Goldstone (DSS-14), bit 1 Madrid (DSS-63), bit 2 Canberra (DSS-43) sees the Moon centre at >= 10 deg. |
| 400 m DEM | `map/dem_400m.bin.gz`, `map/map.json` (only the `dem` block is read) | 2280 x 2280 px at 400 m (half-width 456 km), south polar stereographic, int16 metres above the 1737.4 km sphere, planar-split + gzip. Inside 80 S (the inner 1520 x 1520 px block at offset 380 px, `dem.inner` in `map.json`): LOLA `LDEM_80S_80M` 5 x 5 block means. The ring to about 75 S (edge 75.05 S; corners about 69 S, real LOLA heights, no fill): LOLA `LDEM_75S_120M` exact area-overlap means of the 120 m pixels on each 400 m cell. Used for custom-site heights and coarse horizons and for the light and shadow map (the region view stays on the 80-90 S block). |
| Preset sites | `sites.json` | Site catalog: coordinates, terrain height (LOLA 80 m + 240 m), sources. |
| Preset horizon masks | `horizons.json` | Ray-marched skylines on LOLA `LDEM_80S_80M` + `LDEM_75S_240M`, 0.25 deg azimuth step, centidegrees, observer 2 m and 10 m above terrain, terrain nearer than 120 m ignored. |

## Licence of the data

LOLA (Lunar Orbiter Laser Altimeter, NASA LRO) products and NAIF SPICE kernels are NASA
data and in the public domain in the United States. The derived files above are
redistributed under the same terms; please credit NASA/GSFC LOLA and NASA/JPL NAIF.
The library code is MIT-licensed (see `LICENSE`).

## SHA-256 of every file

Regenerate this table after re-copying (`tests/test_bundled_matches_app.py` checks it).

| File | Bytes | SHA-256 |
|---|---:|---|
| `dsn/2025.bin` | 8,760 | `51d65b5e9675197e0ddfe22ecdfd332636cdf444dbc7adab0c3e48adc2da7314` |
| `dsn/2026.bin` | 8,760 | `591257de8d815375a4db9d2a8eedfc3a13c75b436b60ccee557f4b0cf9b5ab25` |
| `dsn/2027.bin` | 8,760 | `37cfcfa1409894d6982bc98389b902c3152be6f779439c5332f4e7afc0e9179c` |
| `dsn/2028.bin` | 8,784 | `15418bca350821a20b3bf1bf0b48465f8fb4b41c65044c29abc3e73498ac4e77` |
| `dsn/2029.bin` | 8,760 | `652184b47b313922d74b37664f7d8251204cd3ebfda5822b15b459ec6790d565` |
| `dsn/2030.bin` | 8,760 | `30ce55523e25db01d5e880626feb8d70062e16200983ab61db4e04e9c0fc24a4` |
| `dsn/2031.bin` | 8,760 | `16593a220924f482ab99a497742ea9cf34e701643a296553e31aba5b0915f132` |
| `dsn/2032.bin` | 8,784 | `5f0dfb45c0eb6b1f652f1ac12f06fd8ea100b50c0b2a7d96ae14933f23a1baff` |
| `dsn/2033.bin` | 8,760 | `d9cb60a5e1b0a06f9b2db6b28d51026ceda6e74eb9beec0cb8af5df376ef2f09` |
| `dsn/2034.bin` | 8,760 | `b40bf0e7e0a68b6de3da96ef79aad04dd0a688e27ea44a381617223583567042` |
| `dsn/2035.bin` | 8,760 | `0dd63d26030c18c918fc38547424c8c3da637446766133af90580c1140f44903` |
| `ephem/2025.bin` | 210,240 | `7602992505bb78d5d0b0867cd351fa5f3a522418a71294ecdd09b02f71e27ce2` |
| `ephem/2026.bin` | 210,240 | `25986a4e8f31417bbcda3d664fc1d97e6d470366ab743795011e7e99ed2750c2` |
| `ephem/2027.bin` | 210,240 | `a25e1a19bf47e387f02e50761da134258b1638efc77133cc437ff8899d07e91a` |
| `ephem/2028.bin` | 210,816 | `c13e89b669789788d113c6916e0fa0bd7036fb55edc3515baefadb355b9fdd87` |
| `ephem/2029.bin` | 210,240 | `bb4d424e204bfa70d3ddf9d4f6577cc664431857c64201070c479239edd272c9` |
| `ephem/2030.bin` | 210,240 | `f5b72929ceceb2f93d64faaf8022e88a57a83cdf26ba68d8ec1ced76db54ffd3` |
| `ephem/2031.bin` | 210,240 | `2803d7b369d67cbfb0c133de07dc9c1aab02590a1c4417b719e9a3a79ff8be87` |
| `ephem/2032.bin` | 210,816 | `8182c5ba4364c896f9d83ab12e98eeda0a526daa4721682a88824a21a8ef1884` |
| `ephem/2033.bin` | 210,240 | `444bcb9f18326d9c73e0bb3838621168187bf184e5f9b0f0230835a0b1b0ae50` |
| `ephem/2034.bin` | 210,240 | `e0b59fa91f2a219ce7f2c2ebd5e59ab426e367948c47426b0f7359c0ed671242` |
| `ephem/2035.bin` | 210,240 | `a7a610dc921ba697d93ba0a541cf15e44dacf15aeeb2ab95f50cf1ceb32846f0` |
| `ephem/manifest.json` | 3,607 | `6c23d0469929881e2f7abb5e5061e21459665b59fc2413fa9886fa04a48adcd7` |
| `horizons.json` | 288,113 | `874bb481773da50ce8a133303ec52eb7ec68ceeccc711e534926964cc1cf2b4c` |
| `map/dem_400m.bin.gz` | 4,694,460 | `71d285a32a4c1410ffed5c4d8bc62ea8ed04625f443d6f72997fa5d8b0208dbf` |
| `map/map.json` | 3,587 | `dec5ebbe43c177e604047169009b966510bf849323e3b702a7abcdceceb3cc79` |
| `sites.json` | 38,392 | `8eb01e69661a9b20b051d1f8acdf9b7dfc7b6b76a23b124f2f386f97a64f46b2` |
