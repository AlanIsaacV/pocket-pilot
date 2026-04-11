# Ordered list of (keyword, category) tuples.
# First match wins, so more specific keywords go first.
# Category names must match exactly those in defaults.json.

KEYWORD_MAP = [
    # ── Streaming & Digital Services ──
    ("NETFLIX", "Streaming"),
    ("SPOTIFY", "Streaming"),
    ("DISNEY", "Streaming"),
    ("AMAZON PRIME", "Streaming"),
    ("PRIME VIDEO", "Streaming"),
    ("HBO", "Streaming"),
    ("YOUTUBE", "Streaming"),
    ("GOOGLE YOUTUBE", "Streaming"),
    ("APPLE TV", "Streaming"),
    ("CRUNCHYROLL", "Streaming"),
    ("PARAMOUNT", "Streaming"),
    ("STAR+", "Streaming"),

    # ── Internet & Telecom ──
    ("TOTALPLAY", "Internet"),
    ("TELMEX", "Internet"),
    ("IZZI", "Internet"),
    ("MEGACABLE", "Internet"),
    ("TELECABLE", "Internet"),
    ("TELCEL", "Phone"),
    ("AT&T", "Phone"),
    ("MOVISTAR", "Phone"),
    ("UNEFON", "Phone"),

    # ── Software & Cloud ──
    ("APPLE.COM", "Software"),
    ("1PASSWO", "Software"),
    ("CHATGPT", "Software"),
    ("OPENAI", "Software"),
    ("CANVA", "Software"),
    ("ADOBE", "Software"),
    ("GOOGLE STORAGE", "Cloud"),
    ("GOOGLE ONE", "Cloud"),
    ("ICLOUD", "Cloud"),
    ("DROPBOX", "Cloud"),

    # ── Education ──
    ("PLATZI", "Cursos"),
    ("UDEMY", "Cursos"),
    ("COURSERA", "Cursos"),
    ("DOMESTIKA", "Cursos"),
    ("MONTESSORI", "Colegiatura"),

    # ── Food Delivery (before generic transport) ──
    ("UBER EATS", "Restaurante"),
    ("UBER EAT", "Restaurante"),
    ("DIDI FOOD", "Restaurante"),
    ("RAPPI", "Restaurante"),

    # ── Transport ──
    ("UBER TRIP", "Taxi / Uber"),
    ("UBER ", "Taxi / Uber"),
    ("DIDI RIDE", "Taxi / Uber"),
    ("DIDI", "Taxi / Uber"),
    ("D LOCAL*DIDI", "Taxi / Uber"),
    ("DLO*DIDI RIDE", "Taxi / Uber"),
    ("DLO DIDI RIDE", "Taxi / Uber"),
    ("CABIFY", "Taxi / Uber"),

    # ── Grocery / Despensa ──
    ("WALMART", "Despensa"),
    ("SORIANA", "Despensa"),
    ("CHEDRAUI", "Despensa"),
    ("BODEGA AURRERA", "Despensa"),
    ("COSTCO", "Despensa"),
    ("SAM'S CLUB", "Despensa"),
    ("SAMS CLUB", "Despensa"),
    ("LA COMER", "Despensa"),
    ("CITY MARKET", "Despensa"),
    ("FRESKO", "Despensa"),
    ("SUPERAMA", "Despensa"),
    ("HEB ", "Despensa"),
    ("OXXO", "Despensa"),
    ("7 ELEVEN", "Despensa"),
    ("SEVEN ELEVEN", "Despensa"),
    ("CARNICERI", "Despensa"),
    ("CARNEMARTIN", "Despensa"),

    # ── Restaurants & Food ──
    ("MCDONALDS", "Restaurante"),
    ("MCDONALD", "Restaurante"),
    ("DOMINOS", "Restaurante"),
    ("DOMINO'S", "Restaurante"),
    ("STARBUCKS", "Restaurante"),
    ("BURGER KING", "Restaurante"),
    ("LITTLE CAESARS", "Restaurante"),
    ("KFC", "Restaurante"),
    ("SUBWAY", "Restaurante"),
    ("PIZZA HUT", "Restaurante"),
    ("SANBORNS", "Restaurante"),
    ("VIPS", "Restaurante"),
    ("IHOP", "Restaurante"),
    ("TAQUER", "Restaurante"),
    ("REST ", "Restaurante"),
    ("RESTAURANTE", "Restaurante"),
    ("PASTELERIA", "Restaurante"),
    ("GONG CHA", "Restaurante"),
    ("BIGOL BAGEL", "Restaurante"),
    ("DOT COFFE", "Restaurante"),
    ("MATCHA", "Restaurante"),
    ("FATTO", "Restaurante"),
    ("TACO ", "Restaurante"),
    ("TOYO FOODS", "Restaurante"),
    ("LA QUEBRADA", "Restaurante"),

    # ── Shopping ──
    ("AMAZON A MESES", "Compras"),
    ("AMAZON MX A MESES", "Compras"),
    ("STRIPE *AMAZON", "Compras"),
    ("AMAZON", "Compras"),
    ("MERCADOLIBRE", "Compras"),
    ("MERCADO LIBRE", "Compras"),
    ("MERCADO PAGO", "Compras"),
    ("MERPAGO", "Compras"),
    ("LIVERPOOL", "Compras"),
    ("PALACIO DE HIERRO", "Compras"),
    ("COPPEL", "Compras"),
    ("ELEKTRA", "Compras"),
    ("OFFICE DEPOT", "Compras"),
    ("HOME DEPOT", "Compras"),
    ("DOLLARCITY", "Compras"),
    ("ESCALA ", "Compras"),

    # ── Clothing ──
    ("SHEIN", "Ropa y accesorios"),
    ("ZARA", "Ropa y accesorios"),
    ("H&M", "Ropa y accesorios"),
    ("BERSHKA", "Ropa y accesorios"),
    ("PULL&BEAR", "Ropa y accesorios"),
    ("SHASA", "Ropa y accesorios"),
    ("C&A", "Ropa y accesorios"),
    ("SOVIET NOVIAS", "Ropa y accesorios"),

    # ── Pharmacy & Health ──
    ("FARMACIA", "Farmacia"),
    ("FARMACIAS", "Farmacia"),
    ("FARM GUAD", "Farmacia"),
    ("FAR GUAD", "Farmacia"),
    ("GUADALAJARA", "Farmacia"),
    ("SIMILARES", "Farmacia"),
    ("BENAVIDES", "Farmacia"),
    ("SAN PABLO", "Farmacia"),

    # ── Utilities ──
    ("CFE", "Electricidad"),
    ("SIAPA", "Agua"),
    ("AGUA ", "Agua"),
    ("GAS NATURAL", "Gas"),

    # ── Financial ──
    ("COMISION", "Comisiones"),
    ("ANUALIDAD", "Comisiones"),
    ("INTERES", "Intereses"),
    ("IVA", "Intereses"),
    ("SAT ", "taxes"),
    ("SAT REFERENCIADO", "taxes"),

    # ── Fuel & Vehicle ──
    ("GASOLINERA", "Combustible"),
    ("PEMEX", "Combustible"),
    ("ESTACIONAMIENTO", "Estacionamiento"),

    # ── Entertainment ──
    ("CINEPOLIS", "Cine"),
    ("CINEMEX", "Cine"),

    # ── Gaming ──
    ("STEAM", "Videojuegos"),
    ("PLAYSTATION", "Videojuegos"),
    ("XBOX", "Videojuegos"),
    ("NINTENDO", "Videojuegos"),

    # ── Travel ──
    ("AIRBNB", "Alojamiento"),
    ("BOOKING", "Alojamiento"),
    ("HOTEL", "Alojamiento"),
    ("VOLARIS", "Larga distancia"),
    ("VIVAAEROBUS", "Larga distancia"),
    ("AEROMEXICO", "Larga distancia"),

    # ── Payments to card ──
    ("PAGO TDC", "Transferencias"),
    ("BMOVIL", "Transferencias"),
    ("SPEI", "Transferencias"),
    ("TRANSFERENCIA", "Transferencias"),
]


def categorize(concept: str) -> str:
    """Match a transaction concept against the keyword map.
    Returns the category name if matched, empty string otherwise.
    """
    normalized = concept.upper()
    for keyword, category in KEYWORD_MAP:
        if keyword.upper() in normalized:
            return category
    return ""
