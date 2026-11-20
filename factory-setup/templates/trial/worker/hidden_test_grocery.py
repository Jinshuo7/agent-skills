import unittest
from grocery import to_base, combine, shopping_list


class H(unittest.TestCase):
    def test_zero(self): self.assertEqual(to_base(0, "g"), (0, "g"))
    def test_ml(self): self.assertEqual(to_base(250, "ml"), (250, "ml"))
    def test_pcs_and_mass(self):
        with self.assertRaises(ValueError): combine([("egg", 2, "pcs"), ("Egg", 50, "g")])
    def test_pantry_exact(self):
        self.assertEqual(shopping_list([[("rice", 500, "g")]], {"rice": (500, "g")}, {"rice": (500, "g")}), {})
    def test_pantry_other_unit(self):
        self.assertEqual(shopping_list([[("rice", 700, "g")]], {"rice": (0.2, "kg")}, {"rice": (500, "g")}), {"rice": 1})
    def test_pantry_more_than_needed(self):
        self.assertEqual(shopping_list([[("oil", 100, "ml")]], {"oil": (1, "l")}, {"oil": (500, "ml")}), {})
    def test_pack_in_kg(self):
        self.assertEqual(shopping_list([[("flour", 1500, "g")]], {}, {"flour": (1, "kg")}), {"flour": 2})
    def test_no_pack_volume(self):
        self.assertEqual(shopping_list([[("milk", 2.2, "l")]], {}, {}), {"milk": 2200})
    def test_pantry_unused_item(self):
        self.assertEqual(shopping_list([[("rice", 100, "g")]], {"beans": (1, "kg")}, {}), {"rice": 100})
    def test_combine_across_meals_case(self):
        self.assertEqual(shopping_list([[("Rice", 300, "g")], [("rice ", 300, "g")]], {}, {"rice": (500, "g")}), {"rice": 2})


if __name__ == "__main__":
    unittest.main()
