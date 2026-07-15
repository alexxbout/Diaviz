//
//  CacheImagesProduits.swift
//  diaviz
//
//  Created by Alexandre on 15/07/2026.
//

import UIKit

/// Chargeur d'images produits Open Food Facts avec cache mémoire + disque.
///
/// `AsyncImage` recharge à chaque apparition de vue et ne déduplique pas les
/// requêtes — problématique avec `images.openfoodfacts.org`, parfois lent.
/// Ici : cache mémoire (`NSCache`), cache disque (`URLCache` dédié),
/// déduplication des chargements concurrents du même URL, User-Agent OFF et
/// timeout court.
@MainActor
final class CacheImagesProduits {
    static let shared = CacheImagesProduits()

    private let cache = NSCache<NSURL, UIImage>()
    private var chargementsEnCours: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "Diaviz/1.0 (+https://github.com/alexxbout/Diaviz)"]
        session = URLSession(configuration: config)
    }

    /// Image pour un URL — depuis le cache mémoire si possible, sinon disque
    /// ou réseau. `nil` en cas d'échec (l'appelant affiche un fallback).
    func image(pour url: URL) async -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        if let tache = chargementsEnCours[url] { return await tache.value }

        let tache = Task<UIImage?, Never> { [session] in
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return UIImage(data: data)
        }
        chargementsEnCours[url] = tache
        let image = await tache.value
        chargementsEnCours[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}
