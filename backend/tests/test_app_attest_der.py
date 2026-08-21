"""Strict DER decoding coverage for the App Attest certificate nonce."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app_attest import AppAttestError, _der_nonce


def der(tag: int, content: bytes) -> bytes:
    assert len(content) < 128
    return bytes([tag, len(content)]) + content


def test_der_nonce_accepts_the_documented_sequence_shape():
    nonce = bytes(range(32))

    assert _der_nonce(der(0x30, der(0x04, nonce))) == nonce


def test_der_nonce_accepts_apple_explicit_context_wrapper():
    nonce = bytes(range(32))
    extension = der(0x30, der(0xA0, der(0x04, nonce)))

    assert _der_nonce(extension) == nonce


def test_der_nonce_accepts_an_outer_x509_octet_wrapper():
    nonce = bytes(range(32))
    extension = der(0x04, der(0x30, der(0xA0, der(0x04, nonce))))

    assert _der_nonce(extension) == nonce


@pytest.mark.parametrize(
    "extension",
    [
        b"",  # no DER element
        der(0x30, der(0x04, b"too short")),  # nonce is not SHA-256 sized
        der(0x30, der(0x04, bytes(32)) + der(0x04, bytes(32))),  # ambiguous
        der(0x30, der(0xA1, der(0x04, bytes(32)))),  # unsupported wrapper
        b"\x30\x81\x24" + der(0x04, bytes(32)),  # non-minimal DER length
    ],
)
def test_der_nonce_rejects_malformed_or_ambiguous_extensions(extension):
    with pytest.raises(AppAttestError):
        _der_nonce(extension)
