"""Minimal, dependency-free duration reader for M4A/ISO BMFF uploads.

Metering must use the uploaded audio's container metadata, never a duration
field supplied by the client. iOS recordings place `mvhd` in the `moov` atom.
"""

from __future__ import annotations


class AudioDurationError(ValueError):
    """The upload did not expose a safe, parseable M4A duration."""


def duration_seconds(audio_bytes: bytes) -> float:
    marker = audio_bytes.find(b"mvhd")
    if marker < 4:
        raise AudioDurationError("Could not determine uploaded audio duration.")

    atom_start = marker - 4
    atom_size = int.from_bytes(audio_bytes[atom_start:marker], "big")
    content_start = marker + 4
    atom_end = atom_start + atom_size
    if atom_size < 28 or atom_end > len(audio_bytes):
        raise AudioDurationError("Could not determine uploaded audio duration.")

    version = audio_bytes[content_start]
    if version == 0:
        timescale_offset, duration_offset, duration_size = 12, 16, 4
    elif version == 1:
        timescale_offset, duration_offset, duration_size = 20, 24, 8
    else:
        raise AudioDurationError("Could not determine uploaded audio duration.")

    timescale_start = content_start + timescale_offset
    duration_start = content_start + duration_offset
    if duration_start + duration_size > atom_end:
        raise AudioDurationError("Could not determine uploaded audio duration.")

    timescale = int.from_bytes(audio_bytes[timescale_start:timescale_start + 4], "big")
    duration = int.from_bytes(audio_bytes[duration_start:duration_start + duration_size], "big")
    if timescale <= 0 or duration <= 0:
        raise AudioDurationError("Could not determine uploaded audio duration.")
    return duration / timescale
