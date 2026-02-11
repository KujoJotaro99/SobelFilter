#!/usr/bin/env python3
"""UART host script for the Sobel pipeline."""
import argparse
import time
import threading
from pathlib import Path

try:
    import serial
except ImportError as exc:  # pragma: no cover
    raise SystemExit("pyserial is required: pip install pyserial") from exc

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover
    raise SystemExit("Pillow is required: pip install pillow") from exc


DEFAULT_W = 640
DEFAULT_H = 480
DEFAULT_BAUD = 115200
DEFAULT_CHUNK = 2048


def resolve_default_image():
    candidate = Path(__file__).resolve().parents[2] / "jupyter" / "car.jpg"
    return candidate if candidate.exists() else None


def load_image(path, width, height):
    img = Image.open(path).convert("RGB")
    return img.resize((width, height), Image.BILINEAR)


def compute_timeout(byte_count, baud):
    bits = byte_count * 10  # start + 8 data + stop
    seconds = bits / float(baud)
    return max(5.0, seconds * 1.5 + 2.0)


def write_all(ser, payload, chunk_size, delay_s=0.0):
    total = len(payload)
    offset = 0
    while offset < total:
        end = min(offset + chunk_size, total)
        ser.write(payload[offset:end])
        ser.flush()
        offset = end
        if delay_s:
            time.sleep(delay_s)


def read_background(ser, count, timeout_s):
    data = bytearray()
    stop = threading.Event()

    def _worker():
        deadline = time.time() + timeout_s
        while not stop.is_set() and time.time() < deadline:
            remaining = count - len(data)
            if remaining <= 0:
                break
            chunk = ser.read(min(4096, remaining))
            if chunk:
                data.extend(chunk)
            else:
                time.sleep(0.005)

    t = threading.Thread(target=_worker, daemon=True)
    t.start()
    return data, stop, t


def main():
    parser = argparse.ArgumentParser(description="Send image over UART and read it back.")
    parser.add_argument("port", help="Serial port (e.g. /dev/ttyUSB0)")
    parser.add_argument("image", nargs="?", type=Path, default=None, help="Input image (defaults to car.jpg)")

    args = parser.parse_args()

    img_path = args.image or resolve_default_image()
    if img_path is None:
        raise SystemExit("No image specified and default car.jpg not found")

    width = DEFAULT_W
    height = DEFAULT_H
    baud = DEFAULT_BAUD
    pre_delay = 0.2
    chunk = DEFAULT_CHUNK
    chunk_delay = 0.0

    img = load_image(img_path, width, height)
    payload = img.tobytes()
    expected_in_len = len(payload)
    expected_out_len = width * height * 3

    timeout_s = compute_timeout(max(expected_in_len, expected_out_len), baud)

    with serial.Serial(
        args.port,
        baud,
        timeout=0.1,
        write_timeout=timeout_s,
        rtscts=False,
        dsrdtr=False,
        xonxoff=False,
    ) as ser:
        ser.dtr = False
        ser.rts = False
        time.sleep(pre_delay)
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        rx_buf, rx_stop, rx_thread = read_background(ser, expected_out_len, timeout_s)
        write_all(ser, payload, chunk, chunk_delay)

        deadline = time.time() + timeout_s
        while len(rx_buf) < expected_out_len and time.time() < deadline:
            time.sleep(0.05)
        rx_stop.set()
        rx_thread.join(timeout=1.0)
        rx = bytes(rx_buf)

    if len(rx) != expected_out_len:
        partial = Path("sobel_out_partial.png")
        bytes_per_row = width * 3
        if len(rx) >= bytes_per_row:
            rows = len(rx) // bytes_per_row
            partial_img = Image.frombytes("RGB", (width, rows), rx[: rows * bytes_per_row])
            partial_img.save(partial)
        raise SystemExit(f"Short read: got {len(rx)} bytes, expected {expected_out_len}. Wrote {partial}")

    warmup_pixels = (2 * width + 2)
    warmup_bytes = warmup_pixels * 3
    rx = rx[warmup_bytes:] + b"\x00" * warmup_bytes

    out_img = Image.frombytes("RGB", (width, height), rx)
    out_img.save("sobel_out.png")

    print("Wrote sobel_out.png (640x480)")


if __name__ == "__main__":
    main()
