//
//  HistoriqueParametres.swift
//  diaviz
//

import Foundation

/// Règles de l'enregistreur d'historique des paramètres, en logique pure —
/// sans SwiftData, pour être testable seule. `ProfilService.mettreAJour`
/// s'en sert pour décider quelles lignes `ChangementParametre` écrire.
enum HistoriqueParametres {

    /// Valeurs suivies d'un profil, figées à un instant. Une clé absente
    /// vaut `nil` (paramètre non renseigné).
    struct Instantane: Equatable, Sendable {
        var valeurs: [CleParametre: Double] = [:]

        init(valeurs: [CleParametre: Double] = [:]) {
            self.valeurs = valeurs
        }

        /// Les ratios unique et par moment sont relevés quel que soit le
        /// mode : `SectionRatios` efface les valeurs de l'autre mode à la
        /// bascule, et c'est justement une transition à garder.
        ///
        /// La fenêtre d'effet sport est relevée à sa valeur **effective**
        /// (3 h par défaut) : elle s'applique dès le départ, donc la
        /// modifier est un vrai changement, pas une configuration initiale.
        init(profil: ProfilUtilisateur) {
            var v: [CleParametre: Double] = [:]
            v[CleParametre(parametre: .ratioUnique)] = profil.ratioUnique
            let moments = profil.ratiosParMoment
            v[CleParametre(parametre: .ratioPetitDejeuner)] = moments.petitDejeuner
            v[CleParametre(parametre: .ratioDejeuner)] = moments.dejeuner
            v[CleParametre(parametre: .ratioGouter)] = moments.gouter
            v[CleParametre(parametre: .ratioDiner)] = moments.diner
            v[CleParametre(parametre: .facteurCorrection)] = profil.ratioCorrection
            let sport = profil.ratiosSportEffectifs
            for (type, ratio) in sport.parType {
                v[CleParametre(parametre: .ratioSport, typeSport: type)] = ratio
            }
            v[CleParametre(parametre: .fenetreEffetSport)] = sport.fenetreEffetHeures
            valeurs = v
        }
    }

    /// Différence brute entre deux instantanés, sans aucun filtre.
    struct Difference: Equatable, Sendable {
        var cle: CleParametre
        var ancienne: Double?
        var nouvelle: Double?
    }

    /// Toutes les clés dont la valeur a changé, `nil → valeur` compris —
    /// le filtrage des configurations initiales revient à `SessionsEdition`,
    /// qui seule sait d'où partait la saisie en cours.
    static func differences(avant: Instantane, apres: Instantane) -> [Difference] {
        let cles = Set(avant.valeurs.keys).union(apres.valeurs.keys)
        return cles.compactMap { cle in
            let ancienne = avant.valeurs[cle]
            let nouvelle = apres.valeurs[cle]
            guard ancienne != nouvelle else { return nil }
            return Difference(cle: cle, ancienne: ancienne, nouvelle: nouvelle)
        }
        .sorted { ($0.cle.parametre.rawValue, $0.cle.typeSport ?? "") < ($1.cle.parametre.rawValue, $1.cle.typeSport ?? "") }
    }

    /// Ce que l'enregistreur doit faire en base pour une différence.
    enum Decision: Equatable, Sendable {
        /// Rien à écrire : configuration initiale, ou retour à la valeur de
        /// départ sans ligne à effacer.
        case ignorer
        case creer(id: UUID, ancienne: Double?, nouvelle: Double?)
        /// Prolonge la ligne de la saisie en cours avec sa nouvelle valeur
        /// d'arrivée.
        case prolonger(id: UUID, nouvelle: Double?)
        /// La saisie est revenue à sa valeur de départ : la ligne écrite
        /// plus tôt dans la même rafale ne décrit plus aucun changement.
        case supprimer(id: UUID)
    }

    /// Regroupe les saisies rapprochées d'un même paramètre en une seule
    /// transition.
    ///
    /// Sans ça, régler un ratio de 12 à 9 au stepper produirait trois lignes
    /// (12→11, 11→10, 10→9) à quelques secondes d'écart : trois « périodes »
    /// de quelques secondes que la frise devrait ensuite ignorer. Une
    /// session s'ouvre à la première modification d'un paramètre, retient la
    /// valeur de départ, et reste ouverte tant que les saisies se suivent à
    /// moins de `fenetre` d'intervalle.
    ///
    /// Règle héritée de `DatesChangementRatio` : une session partie de `nil`
    /// est une configuration initiale — rien n'est enregistré, même si la
    /// valeur bouge encore plusieurs fois dans la foulée (onboarding,
    /// premier réglage d'un ratio sport).
    ///
    /// État en mémoire seulement : si l'app est tuée pendant une rafale, la
    /// ligne déjà écrite porte la dernière valeur vue — rien n'est perdu, la
    /// saisie suivante ouvrira simplement une nouvelle session.
    struct SessionsEdition: Sendable {

        static let fenetreParDefaut: TimeInterval = 5 * 60

        private struct Session: Sendable {
            var depart: Double?
            var derniereSaisie: Date
            var idLigne: UUID?
        }

        let fenetre: TimeInterval
        private var sessions: [CleParametre: Session] = [:]

        init(fenetre: TimeInterval = SessionsEdition.fenetreParDefaut) {
            self.fenetre = fenetre
        }

        mutating func decider(_ difference: Difference, a date: Date) -> Decision {
            let cle = difference.cle
            var session: Session
            if let courante = sessions[cle], date.timeIntervalSince(courante.derniereSaisie) < fenetre {
                session = courante
                session.derniereSaisie = date
            } else {
                session = Session(depart: difference.ancienne, derniereSaisie: date, idLigne: nil)
            }
            defer { sessions[cle] = session }

            guard let depart = session.depart else { return .ignorer }

            if depart == difference.nouvelle {
                guard let id = session.idLigne else { return .ignorer }
                session.idLigne = nil
                return .supprimer(id: id)
            }
            if let id = session.idLigne {
                return .prolonger(id: id, nouvelle: difference.nouvelle)
            }
            let id = UUID()
            session.idLigne = id
            return .creer(id: id, ancienne: depart, nouvelle: difference.nouvelle)
        }

        /// Oublie les saisies en cours — après une réinitialisation ou un
        /// import, les lignes qu'elles désignaient n'existent plus.
        mutating func oublier() {
            sessions.removeAll()
        }
    }
}
