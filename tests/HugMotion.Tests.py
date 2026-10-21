"""Check fixed-frame preservation and the direction of inverse motion mapping."""
import importlib.util
from pathlib import Path

import numpy as np

spec = importlib.util.spec_from_file_location(
    "hug_motion", Path(__file__).resolve().parents[1] / "tools" / "build-hug-motion.py")
motion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(motion)

height, width = 80, 100
gy, gx = np.mgrid[:height, :width].astype(np.float32)
grid = np.stack((gx, gy), axis=-1)
source = np.zeros((height, width, 3), dtype=np.uint8)
source[20:60, 30:50] = 255
assert np.array_equal(motion.midpoint(source, source, grid), source), "Still frame changed"
displacement = np.zeros((height, width, 2), dtype=np.float32)
displacement[..., 0] = 8
half = motion.warp(source, displacement, 0.5, grid)
assert np.array_equal(half[:, 4:], source[:, :-4]), "Halfway movement has wrong direction or distance"
assert np.array_equal(motion.warp(source, displacement, 0, grid), source), "Start pose changed"
print("PASS: stationary frame, exact start pose and halfway movement")
