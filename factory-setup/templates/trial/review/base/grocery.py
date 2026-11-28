"""Turn meal plans into a grocery list. Implement the functions below."""

import math

UNITS = {"g": ("g", 1), "kg": ("g", 1000), "ml": ("ml", 1), "l": ("ml", 1000), "pcs": ("pcs", 1)}


def to_base(amount, unit):
    """Convert to grams (g, kg) or millilitres (ml, l); 'pcs' stays as pieces.
    Returns (amount, base_unit). Raise ValueError for an unknown unit or a negative amount."""
    if unit not in UNITS:
        raise ValueError("unknown unit: %r" % (unit,))
    if amount < 0:
        raise ValueError("negative amount: %r" % (amount,))
    base, factor = UNITS[unit]
    return amount * factor, base


def combine(ingredients):
    """ingredients: list of (name, amount, unit). Names match case-insensitively and ignore
    surrounding spaces. Return dict name(lowercase) -> (total, base_unit). Mixing a mass unit
    and a volume unit (or pieces) for the same name raises ValueError."""
    totals = {}
    for name, amount, unit in ingredients:
        key = name.strip().lower()
        value, base = to_base(amount, unit)
        if key in totals:
            total, old_base = totals[key]
            if old_base != base:
                raise ValueError("mixed units for %r" % (key,))
            totals[key] = (total + value, base)
        else:
            totals[key] = (value, base)
    return totals


def shopping_list(meals, pantry, pack_sizes):
    """meals: list of ingredient lists (see combine). pantry: dict name -> (amount, unit).
    pack_sizes: dict name -> (size, unit). Return dict name -> number of packs to buy (int),
    after subtracting the pantry. Never negative; omit items needing 0 packs. Items with no
    pack size are bought in base units, rounded up to a whole number."""
    need = combine([item for meal in meals for item in meal])
    for name, (amount, unit) in pantry.items():
        key = name.strip().lower()
        value, _ = to_base(amount, unit)
        if key in need:
            total, base = need[key]
            need[key] = (max(0, total - value), base)

    packs = {}
    for key, (total, base) in need.items():
        if total <= 0:
            continue
        if key in pack_sizes:
            size, unit = pack_sizes[key]
            size_base, _ = to_base(size, unit)
        else:
            size_base = 1
        count = int(math.ceil(total / size_base))
        if count > 0:
            packs[key] = count
    return packs
