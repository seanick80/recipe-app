#!/usr/bin/env python3
"""Download BinhQuocNguyen/food-recognition-model from HuggingFace and convert to CoreML.

Produces two models:
  1. FoodClassifier.mlmodel        — image → food label + confidence
  2. GroceryCategoryClassifier.mlmodel — food name → grocery aisle category

Requires: coremltools, tensorflow, huggingface_hub, Pillow, numpy
Runs on macOS only (coremltools constraint).
"""
import argparse
import os

import numpy as np

MODELS_DIR = os.path.join(
    os.path.dirname(__file__), "..", "RecipeApp", "RecipeApp", "MLModels"
)

# Standard Food-101 class labels (alphabetical).
FOOD101_LABELS = [
    "apple_pie", "baby_back_ribs", "baklava", "beef_carpaccio", "beef_tartare",
    "beet_salad", "beignets", "bibimbap", "bread_pudding", "breakfast_burrito",
    "bruschetta", "caesar_salad", "cannoli", "caprese_salad", "carrot_cake",
    "ceviche", "cheese_plate", "cheesecake", "chicken_curry", "chicken_quesadilla",
    "chicken_wings", "chocolate_cake", "chocolate_mousse", "churros", "clam_chowder",
    "club_sandwich", "crab_cakes", "creme_brulee", "croque_madame", "cup_cakes",
    "deviled_eggs", "donuts", "dumplings", "edamame", "eggs_benedict",
    "escargots", "falafel", "filet_mignon", "fish_and_chips", "foie_gras",
    "french_fries", "french_onion_soup", "french_toast", "fried_calamari", "fried_rice",
    "frozen_yogurt", "garlic_bread", "gnocchi", "greek_salad", "grilled_cheese_sandwich",
    "grilled_salmon", "guacamole", "gyoza", "hamburger", "hot_and_sour_soup",
    "hot_dog", "huevos_rancheros", "hummus", "ice_cream", "lasagna",
    "lobster_bisque", "lobster_roll_sandwich", "macaroni_and_cheese", "macarons",
    "miso_soup", "mussels", "nachos", "omelette", "onion_rings",
    "oysters", "pad_thai", "paella", "pancakes", "panna_cotta",
    "peking_duck", "pho", "pizza", "pork_chop", "poutine",
    "prime_rib", "pulled_pork_sandwich", "ramen", "ravioli", "red_velvet_cake",
    "risotto", "samosa", "sashimi", "scallops", "seaweed_salad",
    "shrimp_and_grits", "spaghetti_bolognese", "spaghetti_carbonara", "spring_rolls",
    "steak", "strawberry_shortcake", "sushi", "tacos", "takoyaki",
    "tiramisu", "tuna_tartare", "waffles",
]

# Map food labels to grocery store aisle categories.
FOOD_TO_CATEGORY = {
    "apple_pie": "Bakery", "baby_back_ribs": "Meat", "baklava": "Bakery",
    "beef_carpaccio": "Meat", "beef_tartare": "Meat", "beet_salad": "Produce",
    "beignets": "Bakery", "bibimbap": "Prepared Foods", "bread_pudding": "Bakery",
    "breakfast_burrito": "Frozen", "bruschetta": "Bakery", "caesar_salad": "Produce",
    "cannoli": "Bakery", "caprese_salad": "Produce", "carrot_cake": "Bakery",
    "ceviche": "Seafood", "cheese_plate": "Dairy", "cheesecake": "Bakery",
    "chicken_curry": "Prepared Foods", "chicken_quesadilla": "Prepared Foods",
    "chicken_wings": "Meat", "chocolate_cake": "Bakery",
    "chocolate_mousse": "Dairy", "churros": "Bakery", "clam_chowder": "Canned Goods",
    "club_sandwich": "Deli", "crab_cakes": "Seafood", "creme_brulee": "Dairy",
    "croque_madame": "Deli", "cup_cakes": "Bakery", "deviled_eggs": "Dairy",
    "donuts": "Bakery", "dumplings": "Frozen", "edamame": "Frozen",
    "eggs_benedict": "Dairy", "escargots": "Seafood", "falafel": "Frozen",
    "filet_mignon": "Meat", "fish_and_chips": "Seafood", "foie_gras": "Deli",
    "french_fries": "Frozen", "french_onion_soup": "Canned Goods",
    "french_toast": "Bakery", "fried_calamari": "Seafood", "fried_rice": "Prepared Foods",
    "frozen_yogurt": "Frozen", "garlic_bread": "Bakery", "gnocchi": "Pasta",
    "greek_salad": "Produce", "grilled_cheese_sandwich": "Dairy",
    "grilled_salmon": "Seafood", "guacamole": "Produce", "gyoza": "Frozen",
    "hamburger": "Meat", "hot_and_sour_soup": "Canned Goods", "hot_dog": "Meat",
    "huevos_rancheros": "Dairy", "hummus": "Deli", "ice_cream": "Frozen",
    "lasagna": "Frozen", "lobster_bisque": "Seafood",
    "lobster_roll_sandwich": "Seafood", "macaroni_and_cheese": "Pasta",
    "macarons": "Bakery", "miso_soup": "International", "mussels": "Seafood",
    "nachos": "Snacks", "omelette": "Dairy", "onion_rings": "Frozen",
    "oysters": "Seafood", "pad_thai": "International", "paella": "Seafood",
    "pancakes": "Bakery", "panna_cotta": "Dairy", "peking_duck": "Meat",
    "pho": "International", "pizza": "Frozen", "pork_chop": "Meat",
    "poutine": "Frozen", "prime_rib": "Meat",
    "pulled_pork_sandwich": "Meat", "ramen": "International", "ravioli": "Pasta",
    "red_velvet_cake": "Bakery", "risotto": "Pasta", "samosa": "Frozen",
    "sashimi": "Seafood", "scallops": "Seafood", "seaweed_salad": "International",
    "shrimp_and_grits": "Seafood", "spaghetti_bolognese": "Pasta",
    "spaghetti_carbonara": "Pasta", "spring_rolls": "Frozen", "steak": "Meat",
    "strawberry_shortcake": "Bakery", "sushi": "Seafood", "tacos": "Meat",
    "takoyaki": "Frozen", "tiramisu": "Bakery", "tuna_tartare": "Seafood",
    "waffles": "Frozen",
}


def build_food_classifier(dest: str) -> None:
    """Download the HF model, convert to CoreML, and save."""
    import coremltools as ct
    import tensorflow as tf
    from huggingface_hub import hf_hub_download

    print("Downloading food-recognition-model from HuggingFace...")
    h5_path = hf_hub_download(
        repo_id="BinhQuocNguyen/food-recognition-model",
        filename="classification_model.h5",
    )
    print(f"Model downloaded to {h5_path}")

    print("Loading Keras model...")
    keras_model = tf.keras.models.load_model(h5_path, compile=False)
    keras_model.summary()

    print("Converting to CoreML...")
    class_labels = [lbl.replace("_", " ").title() for lbl in FOOD101_LABELS]
    mlmodel = ct.convert(
        keras_model,
        inputs=[ct.ImageType(shape=(1, 224, 224, 3), bias=[-1, -1, -1], scale=1 / 127.5)],
        classifier_config=ct.ClassifierConfig(class_labels),
        minimum_deployment_target=ct.target.iOS17,
    )

    mlmodel.author = "BinhQuocNguyen (converted for RecipeApp)"
    mlmodel.short_description = "Food image classifier (101 categories, EfficientNet-B0)"
    mlmodel.license = "MIT"

    os.makedirs(os.path.dirname(dest), exist_ok=True)
    mlmodel.save(dest)
    print(f"Saved FoodClassifier to {dest}")


def build_grocery_classifier(dest: str) -> None:
    """Build a simple nearest-neighbor CoreML model: food name -> grocery category."""
    import coremltools as ct
    from coremltools.models.nearest_neighbors import NearestNeighborsClassifierBuilder

    print("Building grocery category classifier...")

    # Encode each food label as a bag-of-characters feature vector (a-z, 26 dims).
    # This is a simple deterministic encoding that coremltools can handle.
    def encode(name: str) -> list[float]:
        vec = [0.0] * 26
        for ch in name.lower():
            if "a" <= ch <= "z":
                vec[ord(ch) - ord("a")] += 1.0
        return vec

    builder = NearestNeighborsClassifierBuilder(
        input_name="food_features",
        output_name="category",
        number_of_dimensions=26,
        default_class_label="Other",
        number_of_neighbors=1,
    )

    for food, category in FOOD_TO_CATEGORY.items():
        builder.add_samples(
            data_points=np.array([encode(food)]),
            labels=[category],
        )

    mlmodel = builder.create_model()
    mlmodel.author = "RecipeApp"
    mlmodel.short_description = "Maps food names to grocery store aisle categories"
    mlmodel.license = "MIT"

    os.makedirs(os.path.dirname(dest), exist_ok=True)
    ct.models.MLModel(mlmodel).save(dest)
    print(f"Saved GroceryCategoryClassifier to {dest}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert food model to CoreML")
    parser.add_argument(
        "--skip-if-exists",
        action="store_true",
        help="Skip conversion if .mlmodel files already exist",
    )
    args = parser.parse_args()

    food_dest = os.path.join(MODELS_DIR, "FoodClassifier.mlmodel")
    grocery_dest = os.path.join(MODELS_DIR, "GroceryCategoryClassifier.mlmodel")

    if args.skip_if_exists and os.path.exists(food_dest) and os.path.exists(grocery_dest):
        print("ML models already exist, skipping conversion (--skip-if-exists).")
        return

    build_food_classifier(food_dest)
    build_grocery_classifier(grocery_dest)
    print("All ML models converted successfully.")


if __name__ == "__main__":
    main()
