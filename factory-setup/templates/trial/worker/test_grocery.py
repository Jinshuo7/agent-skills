import unittest
from grocery import to_base, combine, shopping_list


class T(unittest.TestCase):
    def test_kg(self): self.assertEqual(to_base(1.5, "kg"), (1500, "g"))
    def test_l(self): self.assertEqual(to_base(2, "l"), (2000, "ml"))
    def test_pcs(self): self.assertEqual(to_base(3, "pcs"), (3, "pcs"))
    def test_bad_unit(self):
        with self.assertRaises(ValueError): to_base(1, "cup")
    def test_negative(self):
        with self.assertRaises(ValueError): to_base(-1, "g")
    def test_combine_case(self):
        self.assertEqual(combine([("Rice", 200, "g"), (" rice ", 0.3, "kg")]), {"rice": (500, "g")})
    def test_combine_mixed(self):
        with self.assertRaises(ValueError): combine([("milk", 1, "l"), ("Milk", 100, "g")])
    def test_list_packs(self):
        meals = [[("rice", 300, "g"), ("milk", 0.5, "l")], [("Rice", 450, "g")]]
        got = shopping_list(meals, {"rice": (200, "g")}, {"rice": (500, "g"), "milk": (1, "l")})
        self.assertEqual(got, {"rice": 2, "milk": 1})
    def test_list_pantry_covers(self):
        got = shopping_list([[("eggs", 4, "pcs")]], {"eggs": (12, "pcs")}, {"eggs": (6, "pcs")})
        self.assertEqual(got, {})
    def test_list_no_pack(self):
        got = shopping_list([[("salt", 2.5, "g")]], {}, {})
        self.assertEqual(got, {"salt": 3})


if __name__ == "__main__":
    unittest.main()
