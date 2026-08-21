import CryptoKit
import DeviceCheck
import Foundation

/// Produces Apple App Attest proof bound to an exact audio payload and endpoint.
/// The private key never leaves the device; the server verifies Apple’s
/// attestation and every subsequent assertion before allowing Free processing.
actor AppAttestationService {
    enum AttestationError: LocalizedError {
        case unsupported
        case malformedChallenge
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unsupported: return "This device cannot verify free processing securely."
            case .malformedChallenge: return "The verification challenge was invalid."
            case .unavailable: return "Device verification is temporarily unavailable."
            }
        }
    }

    private let service = DCAppAttestService.shared
    private let keychain: KeychainService

    init(keychain: KeychainService) {
        self.keychain = keychain
    }

    /// Use a new key when the server confirms that a previously stored key was
    /// never registered. Apple permits an attestation only once per key; keeping
    /// a key whose original attestation was rejected would make every later
    /// attempt fail before it reaches the server.
    func makeAttestation(challenge: Data, replacingUnregisteredKey: Bool = false) async throws -> (keyID: String, object: Data) {
        guard service.isSupported else { throw AttestationError.unsupported }
        let keyID = try await keyIDForAttestation(replacingUnregisteredKey: replacingUnregisteredKey)
        let object = try await withCheckedThrowingContinuation { continuation in
            service.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: challenge))) { object, error in
                if let object { continuation.resume(returning: object) }
                else { continuation.resume(throwing: error ?? AttestationError.unavailable) }
            }
        }
        return (keyID, object)
    }

    func makeAssertion(challenge: Data, protectedPayload: Data) async throws -> (keyID: String, assertion: Data) {
        guard service.isSupported else { throw AttestationError.unsupported }
        guard let keyID = keychain.retrieve(for: .appAttestKeyID) else {
            throw AttestationError.unavailable
        }
        // The server checks this exact SHA-256 against the received body.
        var clientData = challenge
        clientData.append(Data(SHA256.hash(data: protectedPayload)))
        let assertion = try await withCheckedThrowingContinuation { continuation in
            service.generateAssertion(keyID, clientDataHash: Data(SHA256.hash(data: clientData))) { assertion, error in
                if let assertion { continuation.resume(returning: assertion) }
                else { continuation.resume(throwing: error ?? AttestationError.unavailable) }
            }
        }
        return (keyID, assertion)
    }

    private func keyIDForAttestation(replacingUnregisteredKey: Bool) async throws -> String {
        if !replacingUnregisteredKey,
           let keyID = keychain.retrieve(for: .appAttestKeyID) {
            return keyID
        }
        let keyID = try await withCheckedThrowingContinuation { continuation in
            service.generateKey { keyID, error in
                if let keyID { continuation.resume(returning: keyID) }
                else { continuation.resume(throwing: error ?? AttestationError.unavailable) }
            }
        }
        try keychain.save(keyID, for: .appAttestKeyID)
        return keyID
    }
}
