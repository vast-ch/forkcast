"""Hand-made preset routes: ordered lists of towns, routed with BRouter.

Each stop is (country code, name for geocoding[, how]); how the leg arriving
at that stop goes: BRouter if left out, "ferry" for a ferry crossing, or a
EuroVelo route ("ev8") to follow it, joined to the stops with BRouter.
The Interlaken – Málaga route (Rhône valley, then EuroVelo 8 down Spain's east coast) and
Milan – Athens (EuroVelo 8 from the Po valley through the Balkans) are demo routes, not official ones.
EuroVelo routes are not listed here: they come from OpenStreetMap
(see eurovelo.py).
"""

ROUTES = [
    {
        "id": "interlaken-malaga",
        "name": "Interlaken – Málaga",
        "color": "#0f7b8a",
        "url": "",
        "stops": [
            ("ch", "Interlaken"),
            ("ch", "Thun"),
            ("ch", "Bern"),
            ("ch", "Fribourg"),
            ("ch", "Lausanne"),
            ("ch", "Genève"),
            ("fr", "Bellegarde-sur-Valserine"),
            ("fr", "Lyon"),
            ("fr", "Vienne, Isère"),
            ("fr", "Valence, Drôme"),
            ("fr", "Montélimar"),
            ("fr", "Orange, Vaucluse"),
            ("fr", "Avignon"),
            ("fr", "Nîmes"),
            ("fr", "Montpellier"),
            ("es", "Málaga", "ev8"),
        ],
    },
    {
        "id": "milan-athens",
        "name": "Milan – Athens",
        "color": "#b5532a",
        "url": "",
        "stops": [
            ("it", "Milano"),
            ("gr", "Athens", "ev8"),
        ],
    },
]
