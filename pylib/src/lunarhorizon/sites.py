"""Landing sites: the app's preset catalog and user-placed (custom) sites.

A :class:`Site` bundles what a time series needs: the position (planetocentric lat,
east-positive lon), the terrain height above the 1737.4 km sphere and the horizon masks
by observer height (metres above the terrain).

* ``Site.preset("derosa2012-sr1-shackleton-rim")``, ``Site.preset("Shackleton rim (SR1)")`` or ``Site.preset("SR1")``:
  the bundled ``sites.json`` record (height rounded to 0.1 m, exactly what the app uses)
  and the bundled ``horizons.json`` masks (LOLA 80 m + 240 m, 0.25 deg, 2 m and 10 m).
* ``Site.custom(lat, lon)`` (``dem="app"``): exactly the app's custom site: the 400 m
  DEM's bilinear height and its coarse on-device horizon (0.5 deg, ``approximate=True``).
* ``Site.custom(lat, lon, dem="lola")``: the preset method at any spot: LOLA 80 m +
  240 m height and full-resolution horizon (needs ``lunarhorizon.data.fetch("dems")``;
  takes tens of seconds per site).
"""

from __future__ import annotations

import functools
import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from .horizon import HorizonMask, coarse_horizon_mask, horizon_profile, march_distances, preset_masks

__all__ = ["Site", "list_presets"]


@functools.lru_cache(maxsize=1)
def _sites_json() -> dict:
    from .data import bundled_path

    return json.loads(Path(bundled_path("sites.json")).read_text(encoding="utf-8"))


def _records() -> list[dict]:
    return _sites_json()["sites"]


def _short_code(rec: dict) -> str:
    """The lower-case code in brackets at the end of a short name ("Shackleton rim (SR1)" -> "sr1"), or ""."""
    short = str(rec.get("short", "")).strip()
    if short.endswith(")") and "(" in short:
        return short[short.rindex("(") + 1:-1].strip().lower()
    return ""


def list_presets() -> list[dict]:
    """The preset sites: ``[{id, name, short, group, lat, lon}, ...]`` in catalog order."""
    return [{"id": r["id"], "name": r["name"], "short": r.get("short", r["name"]), "group": r.get("group", ""),
             "lat": r["lat"], "lon": r["lon"]} for r in _records()]


@dataclass
class Site:
    """A site with its terrain height and horizon masks.

    Attributes:
        id: catalog id (presets) or ``"custom(lat,lon)"``.
        name: display name.
        lat_deg, lon_deg: planetocentric latitude, east-positive longitude (deg).
        terrain_height_m: terrain height above the 1737.4 km sphere (m).
        masks: horizon masks keyed by observer height above the terrain (m).
        approximate: True for the 400 m coarse horizon (app custom sites).
        meta: the sites.json record (group, kind, sources, notes, ...) for presets.
    """

    id: str
    name: str
    lat_deg: float
    lon_deg: float
    terrain_height_m: float
    masks: dict[float, HorizonMask] = field(default_factory=dict)
    approximate: bool = False
    meta: dict = field(default_factory=dict)
    dem: str = "preset"  # "preset" | "app" | "lola": how masks for new heights are made

    # --- constructors -------------------------------------------------------------
    @classmethod
    def preset(cls, id_or_short_name: str) -> "Site":
        """A preset site by id, short name, name, or the code in brackets at the end of the
        short name (``"SR1"`` for "Shackleton rim (SR1)"); names and codes are case-insensitive.

        Raises ``KeyError`` listing the ids when nothing matches.
        """
        key = str(id_or_short_name).strip()
        recs = _records()
        rec = next((r for r in recs if r["id"] == key), None)
        if rec is None:
            low = key.lower()
            rec = next((r for r in recs if str(r.get("short", "")).lower() == low), None) \
                or next((r for r in recs if str(r.get("name", "")).lower() == low), None)
        if rec is None and low:
            coded = [r for r in recs if _short_code(r) == low]
            rec = coded[0] if len(coded) == 1 else None
        if rec is None:
            raise KeyError(f"no preset site {id_or_short_name!r}; ids: {', '.join(r['id'] for r in recs)}")
        masks = preset_masks().get(rec["id"], {})
        return cls(id=rec["id"], name=rec["name"], lat_deg=float(rec["lat"]), lon_deg=float(rec["lon"]),
                   terrain_height_m=float(rec["terrainHeightM"]), masks=dict(masks), approximate=False,
                   meta=dict(rec), dem="preset")

    @classmethod
    def custom(cls, lat_deg: float, lon_deg: float, *, name: str = "Custom site",
               observer_heights_m=(2.0, 10.0), dem: str = "app") -> "Site":
        """A user-placed site.

        ``dem="app"``: the app's method (400 m DEM bilinear height, coarse horizon on the
        400 m DEM, 0.5 deg; ``approximate=True``). ``dem="lola"``: LOLA 80 m + 240 m
        height and the full-resolution horizon (0.25 deg). Raises ``ValueError`` outside
        the DEM coverage: ``dem="app"`` needs ``-90 <= lat <= -80.01`` (the app's custom-spot
        rule, ``customLatAllowed`` in ``dem.dart``: inside the 80-90 S map; the 400 m DEM
        itself reaches about 75 S, so the horizon sees terrain beyond 80 S), ``dem="lola"``
        needs ``-90 <= lat < -75`` (the 240 m DEM's edge; north of 80 S the height and near
        field come from the 240 m DEM only).
        ``lon_deg`` is normalised to [-180, 180) (400 -> 40).
        """
        from .projection import check_site_latlon

        if dem not in ("app", "lola"):
            raise ValueError(f"dem must be 'app' or 'lola', got {dem!r}")
        lat, lon = check_site_latlon(lat_deg, lon_deg, dem)
        sid = f"custom({lat:.4f},{lon:.4f})"
        heights = tuple(float(h) for h in observer_heights_m)
        if dem == "app":
            h_site, masks = coarse_horizon_mask(lat, lon, heights)
            return cls(id=sid, name=name, lat_deg=lat, lon_deg=lon, terrain_height_m=h_site, masks=masks,
                       approximate=True, meta={"kind": "custom", "dem": "LOLA 400 m (app)"}, dem="app")
        if dem == "lola":
            from .terrain import TerrainModel

            prof = horizon_profile(TerrainModel.lola(), lat, lon, heights, az_step_deg=0.25,
                                   distances_m=march_distances())
            masks = {h: HorizonMask(0.25, prof["elevation"][h], source=f"LOLA 80 m + 240 m DEM, {h:g}m observer")
                     for h in heights}
            return cls(id=sid, name=name, lat_deg=lat, lon_deg=lon, terrain_height_m=prof["h_site_m"],
                       masks=masks, approximate=False,
                       meta={"kind": "custom", "dem": "LOLA 80 m + 240 m"}, dem="lola")
        raise AssertionError("unreachable")  # pragma: no cover - dem checked above

    # --- use ----------------------------------------------------------------------
    @property
    def heights_m(self) -> list[float]:
        """Observer heights (m above terrain) with a mask."""
        return sorted(self.masks)

    def mask(self, observer_height_m: float = 2.0) -> HorizonMask:
        """The horizon mask for an observer height (m above the terrain).

        Presets and app custom sites have fixed heights (``KeyError`` naming them otherwise);
        LOLA custom sites compute a new height on demand.
        """
        h = float(observer_height_m)
        if h in self.masks:
            return self.masks[h]
        if self.dem == "lola":
            from .horizon import horizon_mask

            m = horizon_mask(self.lat_deg, self.lon_deg, h, terrain="lola")
            self.masks[h] = m
            return m
        raise KeyError(f"site {self.id!r} has horizon masks for observer heights {self.heights_m} m only, "
                       f"not {h:g} m")

    def observer(self, observer_height_m: float = 2.0):
        """The :class:`lunarhorizon.sky.Observer` at ``terrain + observer_height_m`` above the sphere."""
        from .sky import Observer

        return Observer(self.lat_deg, self.lon_deg, self.terrain_height_m + float(observer_height_m))

    def to_dict(self) -> dict:
        """JSON-friendly summary (masks as their elevation lists)."""
        return {"id": self.id, "name": self.name, "lat": self.lat_deg, "lon": self.lon_deg,
                "terrainHeightM": self.terrain_height_m, "approximate": self.approximate,
                "masks": {f"{h:g}": {"azStepDeg": m.az_step_deg, "elevDeg": np.asarray(m.elev_deg).tolist(),
                                     "source": m.source} for h, m in self.masks.items()}}

    def __repr__(self) -> str:
        return (f"Site({self.id!r}, lat={self.lat_deg}, lon={self.lon_deg}, h={self.terrain_height_m:.1f} m, "
                f"heights={self.heights_m}, approximate={self.approximate})")
