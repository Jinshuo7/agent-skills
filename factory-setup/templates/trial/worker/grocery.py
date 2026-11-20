"""Turn meal plans into a grocery list. Implement the functions below."""


def to_base(amount, unit):
    """Convert to grams (g, kg) or millilitres (ml, l); 'pcs' stays as pieces.
    Returns (amount, base_unit). Raise ValueError for an unknown unit or a negative amount."""
    raise NotImplementedError


def combine(ingredients):
    """ingredients: list of (name, amount, unit). Names match case-insensitively and ignore
    surrounding spaces. Return dict name(lowercase) -> (total, base_unit). Mixing a mass unit
    and a volume unit (or pieces) for the same name raises ValueError."""
    raise NotImplementedError


def shopping_list(meals, pantry, pack_sizes):
    """meals: list of ingredient lists (see combine). pantry: dict name -> (amount, unit).
    pack_sizes: dict name -> (size, unit). Return dict name -> number of packs to buy (int),
    after subtracting the pantry. Never negative; omit items needing 0 packs. Items with no
    pack size are bought in base units, rounded up to a whole number."""
    raise NotImplementedError
