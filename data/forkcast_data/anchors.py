"""Hand-made preset routes: ordered lists of towns, routed with BRouter.

Each stop is (country code, name for geocoding[, "ferry"]); "ferry" marks
the leg arriving at that stop as a ferry crossing.
The Interlaken – Málaga route (Rhône valley, then Spain's east coast) is a demo route, not an official one.
EuroVelo routes are not listed here: they come from the official GPX tracks
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
            ("fr", "Béziers"),
            ("fr", "Narbonne"),
            ("fr", "Perpignan"),
            ("es", "Figueres"),
            ("es", "Girona"),
            ("es", "Barcelona"),
            ("es", "Sitges"),
            ("es", "Tarragona"),
            ("es", "L'Ametlla de Mar"),
            ("es", "Vinaròs"),
            ("es", "Castelló de la Plana"),
            ("es", "Valencia"),
            ("es", "Gandía"),
            ("es", "Dénia"),
            ("es", "Benidorm"),
            ("es", "Alicante"),
            ("es", "Elche"),
            ("es", "Torrevieja"),
            ("es", "Cartagena"),
            ("es", "Águilas"),
            ("es", "Mojácar"),
            ("es", "Almería"),
            ("es", "Adra"),
            ("es", "Motril"),
            ("es", "Almuñécar"),
            ("es", "Nerja"),
            ("es", "Málaga"),
        ],
    },
]
