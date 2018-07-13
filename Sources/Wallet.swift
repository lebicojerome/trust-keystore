// Copyright © 2017-2018 Trust.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation
import TrustCore

/// Blockchain wallet.
public final class Wallet: Hashable {
    /// Unique wallet identifier.
    public let identifier: String

    /// URL for the key file on disk.
    public var keyURL: URL

    /// Encrypted wallet key
    public var key: KeystoreKey

    /// Wallet type.
    public var type: WalletType {
        return key.type
    }

    /// Wallet accounts.
    public internal(set) var accounts = [Account]()

    /// Creates a `Wallet` from an encrypted key.
    public init(keyURL: URL, key: KeystoreKey) {
        identifier = keyURL.deletingPathExtension().lastPathComponent
        self.keyURL = keyURL
        self.key = key
    }

    /// Returns the only account for non HD-wallets.
    ///
    /// - Parameter password: wallet encryption password
    /// - Returns: the account
    /// - Throws: `WalletError.invalidKeyType` if this is an HD wallet `DecryptError.invalidPassword` if the
    ///           password is incorrect.
    public func getAccount(password: String) throws -> Account {
        guard key.type == .encryptedKey else {
            throw WalletError.invalidKeyType
        }

        if let account = accounts.first {
            return account
        }

        guard let address = PrivateKey(data: try key.decrypt(password: password))?.publicKey(for: .ethereum).address else {
            throw DecryptError.invalidPassword
        }

        let account = Account(wallet: self, address: address, derivationPath: Blockchain.ethereum.derivationPath(at: 0))
        accounts.append(account)
        return account
    }

    /// Returns accounts for specific derivation paths.
    ///
    /// - Parameters:
    ///   - blockchain: blockchain this account is for
    ///   - derivationPaths: array of HD derivation paths
    ///   - password: wallet encryption password
    /// - Returns: the accounts
    /// - Throws: `WalletError.invalidKeyType` if this is not an HD wallet `DecryptError.invalidPassword` if the
    ///           password is incorrect.
    public func getAccounts(blockchain: Blockchain, derivationPaths: [DerivationPath], password: String) throws -> [Account] {
        guard key.type == .hierarchicalDeterministicWallet else {
            throw WalletError.invalidKeyType
        }

        guard var mnemonic = String(data: try key.decrypt(password: password), encoding: .ascii) else {
            throw DecryptError.invalidPassword
        }
        defer {
            mnemonic.clear()
        }

        var accounts = [Account]()
        let wallet = HDWallet(mnemonic: mnemonic, passphrase: key.passphrase)
        for derivationPath in derivationPaths {
            let account = getAccount(wallet: wallet, blockchain: blockchain, derivationPath: derivationPath)
            accounts.append(account)
        }

        return accounts
    }

    private func getAccount(wallet: HDWallet, blockchain: Blockchain, derivationPath: DerivationPath) -> Account {
        let address = wallet.getKey(at: derivationPath).publicKey(for: blockchain).address

        if let account = accounts.first(where: { $0.address.data == address.data }) {
            return account
        }

        let account = Account(wallet: self, address: address, derivationPath: derivationPath)
        accounts.append(account)
        return account
    }

    public var hashValue: Int {
        return identifier.hashValue
    }

    public static func == (lhs: Wallet, rhs: Wallet) -> Bool {
        return lhs.identifier == rhs.identifier
    }
}

/// Support account types.
public enum WalletType {
    case encryptedKey
    case hierarchicalDeterministicWallet
}

public enum WalletError: LocalizedError {
    case invalidKeyType
}
