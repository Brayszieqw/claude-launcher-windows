"""Render the existing 30 fps hug at 60 fps without changing its poses or timing.

The DIS flow and inverse-warp method is adapted from
mytjxs/codex-startup-animation v1.0.0, tools/build_eye_motion.py.
Requires Python, OpenCV, NumPy and FFmpeg only when rebuilding the media.
"""
import argparse
import subprocess
from pathlib import Path

import cv2
import numpy as np


def flow(a, b):
    solver = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
    # Full-frame footage uses one coarser pyramid level than the reference's small eyelid patches.
    solver.setFinestScale(1)
    solver.setPatchSize(8)
    solver.setPatchStride(3)
    solver.setGradientDescentIterations(50)
    solver.setVariationalRefinementIterations(10)
    result = solver.calc(cv2.cvtColor(a, cv2.COLOR_BGR2GRAY),
                         cv2.cvtColor(b, cv2.COLOR_BGR2GRAY), None)
    return cv2.GaussianBlur(result, (5, 5), 1.0)


def warp(image, displacement, amount, grid):
    coordinates = grid.copy()
    for _ in range(4):
        sampled = cv2.remap(displacement, coordinates[..., 0], coordinates[..., 1],
                            cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
        coordinates = grid - amount * sampled
    return cv2.remap(image, coordinates[..., 0], coordinates[..., 1],
                     cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE).astype(np.float32)


def midpoint(a, b, grid):
    if np.array_equal(a, b):
        return a
    first = warp(a, flow(a, b), 0.5, grid)
    second = warp(b, flow(b, a), 0.5, grid)
    return np.clip(np.rint((first + second) * 0.5), 0, 255).astype(np.uint8)


def render(source, destination):
    if source.resolve() == destination.resolve() or destination.exists():
        raise ValueError("Use a new output path; preserve the original animation.")
    capture = cv2.VideoCapture(str(source))
    if not capture.isOpened():
        raise ValueError("Cannot open source animation")
    encoder = None
    decoder = None
    try:
        width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = capture.get(cv2.CAP_PROP_FPS)
        count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
        if (width, height, count) != (1586, 992, 300) or abs(fps - 30) > 0.01:
            raise ValueError("Expected the original 1586 x 992, 300-frame, 30 fps hug")
        capture.release()
        # FFmpeg honors the original BT.709 matrix; OpenCV's decoder changes these colors.
        decoder = subprocess.Popen([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(source),
            "-f", "rawvideo", "-pix_fmt", "bgr24", "-"], stdout=subprocess.PIPE)
        frame_bytes = width * height * 3
        raw = decoder.stdout.read(frame_bytes)
        if len(raw) != frame_bytes:
            raise ValueError("Cannot decode the first frame")
        previous = np.frombuffer(raw, dtype=np.uint8).reshape(height, width, 3)
        gy, gx = np.mgrid[:height, :width].astype(np.float32)
        grid = np.stack((gx, gy), axis=-1)
        encoder = subprocess.Popen([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-n",
            "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{width}x{height}",
            "-r", "60", "-i", "-", "-an", "-c:v", "libx264", "-preset", "slow",
            "-crf", "12", "-vf", "scale=in_range=pc:out_range=pc:out_color_matrix=bt709",
            "-pix_fmt", "yuv420p", "-color_range", "pc", "-colorspace", "bt709",
            "-color_primaries", "bt709", "-color_trc", "bt709", "-movflags", "+faststart",
            str(destination)], stdin=subprocess.PIPE)
        emitted = 0
        for index in range(1, count):
            raw = decoder.stdout.read(frame_bytes)
            if len(raw) != frame_bytes:
                raise ValueError(f"Source decoding stopped at frame {index}")
            current = np.frombuffer(raw, dtype=np.uint8).reshape(height, width, 3)
            encoder.stdin.write(previous.tobytes())
            encoder.stdin.write(midpoint(previous, current, grid).tobytes())
            emitted += 2
            previous = current
            if index % 30 == 0:
                print(f"Rendered {emitted}/600 frames", flush=True)
        if decoder.stdout.read(1) or decoder.wait() != 0:
            raise ValueError("Source frame count changed or decoding failed")
        # Keep the original final hold and exactly ten seconds of playback.
        encoder.stdin.write(previous.tobytes())
        encoder.stdin.write(previous.tobytes())
        emitted += 2
        encoder.stdin.close()
        if encoder.wait() != 0:
            raise RuntimeError("FFmpeg encoding failed")
        assert emitted == 600
        print("PASS: 600 frames / 60 fps / 10 seconds; all source poses retained", flush=True)
    finally:
        capture.release()
        if encoder and encoder.poll() is None:
            encoder.kill()
            encoder.wait()
        if decoder and decoder.poll() is None:
            decoder.kill()
            decoder.wait()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    cv2.setNumThreads(2)
    render(arguments.source, arguments.destination)
