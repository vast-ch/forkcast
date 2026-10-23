"""The regions the app is split into. Each one is downloaded separately by the app.

Bounding boxes are (lon_min, lat_min, lon_max, lat_max) in degrees, on the
0.5° grid, generous enough that neighbouring regions overlap a little.
Antarctica is left out (no riding there to plan).
"""

CONTINENTS = [
    {"id": "europe", "name": "Europe", "bbox": (-25.0, 27.0, 45.0, 72.0)},
    {"id": "africa", "name": "Africa", "bbox": (-26.0, -36.0, 56.0, 38.0)},
    {"id": "asia", "name": "Asia", "bbox": (25.0, -11.0, 180.0, 78.0)},
    {"id": "north-america", "name": "North America", "bbox": (-170.0, 7.0, -50.0, 75.0)},
    {"id": "south-america", "name": "South America", "bbox": (-82.0, -56.0, -34.0, 13.0)},
    {"id": "oceania", "name": "Oceania", "bbox": (110.0, -48.0, 180.0, 0.0)},
]
