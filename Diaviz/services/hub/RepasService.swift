//
//  RepasService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

/// Service du domaine Repas, branché sur le hub SwiftData. Lit et écrit
/// réellement les `Repas` (fait brut horodaté + ses `Aliment`).
///
/// Pattern de démarrage aligné sur `InjectionsService` : la vue crée le
/// service vide puis lui passe le `ModelContext` de l'environnement via `.task`.
/// Le service garde le contexte, recharge `repas` après chaque mutation et
/// l'expose en `@Observable` pour rafraîchir la vue.
///
/// « Un hub, des dérivations » : le service ne persiste que des faits bruts.
/// La réponse glycémique d'un repas (`Repas.etatAnalyse`) est une dérivation
/// `@Transient` — laissée à `nil` côté hub (aucun assembleur CGM branché pour
/// l'instant).
@Observable
@MainActor
final class RepasService {

    /// Contexte du hub, fourni au démarrage. `nil` tant que `demarrer` n'a pas
    /// été appelé — toutes les opérations sont alors des no-op (dégradation
    /// gracieuse plutôt que crash).
    private var contexte: ModelContext?

    /// Tous les repas du hub, triés par heure ascendante. Rechargé depuis le
    /// store après chaque écriture.
    private(set) var repas: [Repas] = []

    /// Avance après chaque recalcul des courbes : `etatAnalyse` change sur
    /// place, sans que la liste `repas` soit remplacée.
    private(set) var revisionCourbes = 0

    // MARK: - Démarrage

    /// Branche le service sur le contexte du hub et charge les données. Idempotent.
    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        recharger()
    }

    // MARK: - Lecture par jour

    /// Repas d'un jour donné, triés par heure ascendante.
    func repasDuJour(_ jour: Date) -> [Repas] {
        let cal = Calendar.current
        return repas
            .filter { cal.isDate($0.heure, inSameDayAs: jour) }
            .sorted { $0.heure < $1.heure }
    }

    /// Regroupe les repas d'un jour donné dans les 4 sections canoniques du
    /// journal (« Petit déjeuner », « Déjeuner », « En-cas », « Dîner »), dans
    /// l'ordre attendu par `ListeRepasParSection`. Les sections vides sont
    /// conservées (la vue affiche un état « Aucun repas enregistré »).
    ///
    /// Format identique au tuple historique `[(titre:, repas:)]` consommé par
    /// `JournalVue` / `ListeRepasParSection`, pour brancher la lecture sans
    /// toucher à la signature de ces vues.
    func sectionsDuJour(_ jour: Date) -> [(titre: String, repas: [Repas])] {
        let duJour = repasDuJour(jour)
        let horaires = horairesRepas
        return SectionRepas.allCases.map { section in
            (titre: section.titre, repas: duJour.filter { $0.section(horaires: horaires) == section })
        }
    }

    /// Horaires de repas configurés dans le profil — sert à classer un repas
    /// dans sa section (« Déjeuner »…) selon les heures de début réglées,
    /// plutôt que des seuils fixes en dur.
    private var horairesRepas: HorairesRepas {
        ProfilService.shared.profil.horairesRepas
    }

    // MARK: - Dérivations pour l'UI d'injection
    //
    // Le hub stocke le site d'injection sur l'`Injection`, jamais sur le
    // `Repas`. Ces deux lectures rapatrient l'info côté repas au lieu de la
    // dupliquer ou de la mocker.

    /// Zone de la dernière injection **rapide** (bolus repas ou correction)
    /// enregistrée dans le hub. Alimente l'avertissement anti-lipodystrophie du
    /// sélecteur de site. `nil` si aucune injection rapide connue.
    func derniereZoneRapide() -> ZoneInjection? {
        guard let contexte else { return nil }
        let descripteur = FetchDescriptor<Injection>(
            sortBy: [SortDescriptor(\.heure, order: .reverse)]
        )
        let injections = (try? contexte.fetch(descripteur)) ?? []
        return injections.first {
            $0.type == .rapideRepas || $0.type == .rapideCorrection
        }?.zoneInjection
    }

    /// Site (zone + côté) du bolus repas lié à un repas, s'il existe. Permet à
    /// `DetailRepasVue` d'afficher le vrai site plutôt qu'un « — » permanent.
    func siteBolus(repasId: UUID) -> SiteInjection? {
        guard let contexte else { return nil }
        let descripteur = FetchDescriptor<Injection>(
            predicate: #Predicate { $0.repasAssocieId == repasId }
        )
        guard let bolus = try? contexte.fetch(descripteur).first else { return nil }
        return SiteInjection(zone: bolus.zoneInjection, cote: bolus.coteInjection)
    }

    /// Nombre de repas (non vides) enregistrés aujourd'hui — alimente le
    /// sous-titre de la carte « Repas » du journal.
    var nombreRepasAujourdhui: Int {
        repasDuJour(Date()).filter { !$0.aliments.isEmpty }.count
    }

    // MARK: - Écriture

    /// Enregistre un repas (création ou édition). **Upsert par `id`** : si un
    /// repas de même `id` existe déjà, il est supprimé puis remplacé (la
    /// relation cascade nettoie ses anciens `Aliment`).
    /// - Parameter notifier: `false` pour une restauration après annulation —
    ///   la pilule ferait doublon avec celle qui vient d'être utilisée.
    func enregistrer(_ unRepas: Repas, notifier: Bool = true) {
        guard let contexte else { return }
        // Confirmation éphémère : la sheet se ferme sans rien dire de ce qui a
        // été écrit. Émise ici et non aux points d'appel — tous y passent.
        if notifier {
            ToastsService.shared.afficher(
                .repas,
                titre: "Repas enregistré",
                detail: detailToast(unRepas)
            )
        }
        let cible = unRepas.id
        let descripteur = FetchDescriptor<Repas>(predicate: #Predicate { $0.id == cible })
        if let existant = try? contexte.fetch(descripteur).first, existant !== unRepas {
            contexte.delete(existant)
        }
        contexte.insert(unRepas)
        try? contexte.save()
        recharger()
    }

    /// Construit puis enregistre un repas depuis les entrées de saisie. Point
    /// d'entrée appelé à la validation de `RepasSheet`. Les `EntreeAliment`
    /// (saisie, en grammes, liées à `AlimentCiqual`) sont mappées en `Aliment`
    /// du hub (voir `Aliment.init(depuis:)`).
    ///
    /// Les entrées sans aliment ne produisent rien : on n'enregistre pas un
    /// repas vide.
    @discardableResult
    /// Remplace les événements d'un repas déjà enregistré et resauvegarde.
    ///
    /// Passe par `Repas.remplacerEvenements` pour solder au passage les champs
    /// legacy : sans ça, retirer tous les événements d'un ancien repas le
    /// laisserait afficher son `contexteLibre` d'origine, reconstruit par
    /// `evenementsAffiches`.
    ///
    /// Conséquence à connaître : ajouter ou retirer un événement change
    /// l'éligibilité du repas au mining du ratio (`AnalyseRatioService`
    /// exclut sur `aUnEvenement`), d'où le recalcul demandé par l'appelant
    /// après cette écriture.
    func mettreAJourEvenements(_ evenements: [EvenementRepas], sur repas: Repas) {
        repas.remplacerEvenements(evenements)
        try? contexte?.save()
        rattacherEvenementsNonResolus(de: repas)
        recharger()
    }

    /// Rattache en tâche de fond les événements saisis sans passer par le
    /// référentiel (`idReferentiel == nil`) — cas d'un ajout fait alors que
    /// Foundation Models était indisponible. Jamais bloquant : si la
    /// résolution échoue, l'événement garde son libellé brut indéfiniment,
    /// sans retry.
    private func rattacherEvenementsNonResolus(de repas: Repas) {
        let aResoudre = repas.evenements.filter { $0.idReferentiel == nil }
        guard !aResoudre.isEmpty else { return }
        Task {
            for evenement in aResoudre {
                let texte = evenement.texteBrut ?? evenement.libelle
                guard let resultat = await ReferentielContextesService.shared.resoudre(texte: texte) else { continue }
                guard let idx = repas.evenements.firstIndex(where: { $0.id == evenement.id }) else { continue }
                repas.evenements[idx].idReferentiel = resultat.id
                repas.evenements[idx].libelle = resultat.libelle
                repas.evenements[idx].emoji = resultat.emoji
            }
            try? contexte?.save()
        }
    }

    func enregistrerDepuisSaisie(
        entrees: [EntreeAliment],
        heure: Date = Date(),
        doseInjectee: Double = 0,
        site: SiteInjection = .parDefaut,
        doseGlobale: Double? = nil,
        doseCorrection: Double = 0,
        ajustements: [Ajustement] = [],
        evenements: [EvenementRepas] = [],
        exclureDesAnalyses: Bool = false,
        momentChoisi: SectionRepas? = nil
    ) -> Repas? {
        let alimentsHub = entrees.map(Aliment.init(depuis:))
        guard !alimentsHub.isEmpty else { return nil }
        // Mode « dose globale » : la dose vit sur le repas, pas sur les
        // aliments — on neutralise d'éventuelles doses par aliment saisies
        // avant la bascule, sinon `CarteAlimentEnregistre` afficherait une
        // ventilation qui ne correspond plus à rien.
        if doseGlobale != nil {
            for aliment in alimentsHub { aliment.insuline = 0 }
        }
        let nouveau = Repas(
            heure: heure, aliments: alimentsHub, doseGlobale: doseGlobale,
            doseCorrection: doseCorrection > 0 ? doseCorrection : nil,
            ajustements: ajustements,
            evenements: evenements,
            exclureDesAnalyses: exclureDesAnalyses
        )
        nouveau.momentChoisi = momentChoisi?.rawValue
        // IOB actif juste avant le repas — snapshot figé du contexte insuline
        // (dérivé du hub à la saisie, donc avant le bolus de ce repas). `nil` si
        // négligeable, pour ne pas afficher un badge « 0u ».
        if let contexte {
            let iob = IOBService.iobDuHub(a: heure, contexte: contexte)
            nouveau.iobAuDebut = iob > 0.05 ? iob : nil
        }
        enregistrer(nouveau)

        rattacherEvenementsNonResolus(de: nouveau)

        // Bolus repas → `Injection` rapide liée au repas dans le hub. C'est elle
        // que lisent l'IOB et la section « Bolus repas » de Médications (le hub
        // ne déduit pas l'insuline depuis les aliments). Rien créé sans dose.
        if doseInjectee > 0, let contexte {
            contexte.insert(nouveauBolus(de: nouveau, dose: doseInjectee, site: site))
            try? contexte.save()
        }
        return nouveau
    }

    private func nouveauBolus(de unRepas: Repas, dose: Double, site: SiteInjection) -> Injection {
        Injection(
            type: .rapideRepas,
            dose: dose,
            heure: unRepas.heure,
            zoneInjection: site.zone,
            coteInjection: site.cote,
            repasAssocieId: unRepas.id,
            labelRepas: unRepas.section(horaires: horairesRepas).titre,
            emojiRepas: unRepas.emojiPrincipal,
            motif: .repas,
            source: .manuel
        )
    }

    /// Réécrit un repas déjà enregistré depuis la saisie. Modification **sur
    /// place** : le repas garde son `id`, donc son masquage éventuel dans
    /// « Repas à revoir » et les liens qui pointent vers lui.
    ///
    /// Le bolus lié suit la dose, l'heure et le site : recréé s'il avait été
    /// supprimé, retiré si la dose tombe à zéro. Les dérivés (verdict, ratio)
    /// sont repris par `recharger()` tant que le repas est dans la fenêtre
    /// d'analyse.
    func modifier(
        _ unRepas: Repas,
        entrees: [EntreeAliment],
        heure: Date,
        doseInjectee: Double,
        site: SiteInjection,
        doseGlobale: Double?,
        doseCorrection: Double,
        ajustements: [Ajustement],
        evenements: [EvenementRepas],
        exclureDesAnalyses: Bool,
        momentChoisi: SectionRepas?
    ) {
        guard let contexte, !entrees.isEmpty else { return }
        let heureChangee = unRepas.heure != heure

        // Un `Aliment` retiré de la relation n'est pas emporté par la cascade.
        let anciens = unRepas.aliments
        let nouveaux = entrees.map(Aliment.init(depuis:))
        if doseGlobale != nil {
            for aliment in nouveaux { aliment.insuline = 0 }
        }
        unRepas.aliments = nouveaux
        for aliment in anciens { contexte.delete(aliment) }

        unRepas.heure = heure
        unRepas.doseGlobale = doseGlobale
        unRepas.doseCorrection = doseCorrection > 0 ? doseCorrection : nil
        unRepas.ajustements = ajustements
        unRepas.remplacerEvenements(evenements)
        unRepas.exclureDesAnalyses = exclureDesAnalyses
        unRepas.dateModification = Date()
        unRepas.momentChoisi = momentChoisi?.rawValue

        // Avant le calcul d'IOB : à sa nouvelle heure, le bolus de ce repas
        // n'entre pas dans l'insuline active « juste avant ».
        synchroniserBolus(de: unRepas, dose: doseInjectee, site: site, contexte: contexte)
        if heureChangee {
            let iob = IOBService.iobDuHub(a: heure, contexte: contexte)
            unRepas.iobAuDebut = iob > 0.05 ? iob : nil
        }
        reinitialiserDerives(de: unRepas, heureChangee: heureChangee)

        try? contexte.save()
        recharger()
        rattacherEvenementsNonResolus(de: unRepas)
        ToastsService.shared.afficher(.repas, titre: "Repas modifié", detail: detailToast(unRepas))
    }

    private func synchroniserBolus(
        de unRepas: Repas, dose: Double, site: SiteInjection, contexte: ModelContext
    ) {
        var bolus = bolusLies(repasId: unRepas.id, contexte: contexte)
        guard dose > 0 else {
            for injection in bolus { contexte.delete(injection) }
            return
        }
        guard let principal = bolus.first else {
            contexte.insert(nouveauBolus(de: unRepas, dose: dose, site: site))
            return
        }
        bolus.removeFirst()
        for injection in bolus { contexte.delete(injection) }
        principal.dose = dose
        principal.heure = unRepas.heure
        principal.zoneInjection = site.zone
        principal.coteInjection = site.cote
        principal.labelRepas = unRepas.section(horaires: horairesRepas).titre
        principal.emojiRepas = unRepas.emojiPrincipal
    }

    /// Verdict et ratio persistés après une modification. Hors de la fenêtre
    /// d'analyse rien ne les recalculera : une courbe déplacée ou un repas
    /// devenu sans insuline ne garde pas son ancien verdict, et le ratio suit
    /// la nouvelle dose.
    private func reinitialiserDerives(de unRepas: Repas, heureChangee: Bool) {
        guard unRepas.verdictPersiste != nil else { return }
        let doseCouvrante = unRepas.totalInsuline - (unRepas.doseCorrection ?? 0)
        if heureChangee || !unRepas.aUneInjection {
            unRepas.verdictPersiste = nil
            unRepas.raisonMauvaisPersistee = nil
            unRepas.ratioEffectifPersiste = nil
        } else {
            unRepas.ratioEffectifPersiste = unRepas.totalGlucides > 0 && doseCouvrante > 0
                ? Double(unRepas.totalGlucides) / doseCouvrante : nil
        }
    }

    /// « 62 g · 6u » — les deux chiffres qui comptent pour un repas. La dose
    /// est celle réellement injectée (ajustements et correction compris), pas
    /// la seule dose de base : c'est ce que l'utilisateur vient de faire.
    private func detailToast(_ unRepas: Repas) -> String {
        let glucides = "\(unRepas.totalGlucides) g"
        guard unRepas.totalInjecte > 0 else { return glucides }
        return "\(glucides) · \(unRepas.totalInjecte.doseInsulineFormatee)"
    }

    /// Supprime un repas du hub (ses aliments suivent via la cascade), ainsi que
    /// son bolus `Injection` lié — sinon l'IOB compterait une dose fantôme.
    func supprimer(_ unRepas: Repas) {
        guard let contexte else { return }
        // Snapshots pris avant la suppression : une fois l'objet retiré du
        // contexte, ses propriétés ne sont plus lisibles. Le bolus lié part
        // avec le repas, il doit donc revenir avec lui.
        let copieRepas = Self.copie(de: unRepas)
        let copiesBolus = bolusLies(repasId: unRepas.id, contexte: contexte).map(Self.copieInjection(de:))
        let detail = detailToast(unRepas)

        supprimerBolusLie(repasId: unRepas.id, contexte: contexte)
        contexte.delete(unRepas)
        try? contexte.save()
        recharger()

        ToastsService.shared.afficherSuppression(titre: "Repas supprimé", detail: detail) { [weak self] in
            guard let self, let contexte = self.contexte else { return }
            for bolus in copiesBolus { contexte.insert(bolus) }
            self.enregistrer(copieRepas, notifier: false)
        }
    }

    /// Duplique un repas et ses aliments. **À tenir à jour** avec
    /// `Repas.init` : un champ oublié ici serait silencieusement perdu à la
    /// restauration. `etatAnalyse` n'en fait pas partie — dérivation
    /// `@Transient`, recalculée au rechargement.
    private static func copie(de unRepas: Repas) -> Repas {
        let copie = Repas(
            id: unRepas.id,
            heure: unRepas.heure,
            aliments: unRepas.aliments.map { aliment in
                Aliment(
                    id: aliment.id, emoji: aliment.emoji, nom: aliment.nom,
                    quantite: aliment.quantite, glucides: aliment.glucides,
                    insuline: aliment.insuline, imageURL: aliment.imageURL,
                    resucrage: aliment.resucrage, idCiqualSource: aliment.idCiqualSource,
                    taillePortion: aliment.taillePortion, codeProduitOFF: aliment.codeProduitOFF
                )
            },
            iobAuDebut: unRepas.iobAuDebut,
            doseGlobale: unRepas.doseGlobale,
            doseCorrection: unRepas.doseCorrection,
            verdictPersiste: unRepas.verdictPersiste,
            raisonMauvaisPersistee: unRepas.raisonMauvaisPersistee,
            ratioEffectifPersiste: unRepas.ratioEffectifPersiste,
            ajustements: unRepas.ajustements,
            evenements: unRepas.evenements,
            contexteLibre: unRepas.contexteLibre,
            contexteNormalise: unRepas.contexteNormalise,
            exclureDesAnalyses: unRepas.exclureDesAnalyses
        )
        copie.dateModification = unRepas.dateModification
        copie.momentChoisi = unRepas.momentChoisi
        return copie
    }

    private static func copieInjection(de injection: Injection) -> Injection {
        Injection(
            id: injection.id, type: injection.type, dose: injection.dose, heure: injection.heure,
            zoneInjection: injection.zoneInjection, coteInjection: injection.coteInjection,
            note: injection.note, glycemieAuMoment: injection.glycemieAuMoment,
            repasAssocieId: injection.repasAssocieId, nomMedicament: injection.nomMedicament,
            labelRepas: injection.labelRepas, emojiRepas: injection.emojiRepas,
            motif: injection.motif, source: injection.source
        )
    }

    private func bolusLies(repasId: UUID, contexte: ModelContext) -> [Injection] {
        let descripteur = FetchDescriptor<Injection>(
            predicate: #Predicate { $0.repasAssocieId == repasId }
        )
        return (try? contexte.fetch(descripteur)) ?? []
    }

    /// Supprime un aliment isolé d'un repas. Si c'était le dernier, le repas
    /// devenu vide est retiré aussi (avec son bolus lié) — un repas sans aliment
    /// n'a pas de sens.
    func supprimerAliment(_ aliment: Aliment, de unRepas: Repas) {
        guard let contexte else { return }
        let deviendraitVide = unRepas.aliments.filter { $0.id != aliment.id }.isEmpty
        contexte.delete(aliment)
        if deviendraitVide {
            supprimerBolusLie(repasId: unRepas.id, contexte: contexte)
            contexte.delete(unRepas)
        }
        try? contexte.save()
        recharger()
    }

    /// Supprime les injections bolus liées à un repas (via `repasAssocieId`).
    /// La dose d'un aliment retiré sans vider le repas n'est PAS recalculée :
    /// le bolus est un fait déjà injecté, pas un dérivé des aliments.
    private func supprimerBolusLie(repasId: UUID, contexte: ModelContext) {
        let descripteur = FetchDescriptor<Injection>(
            predicate: #Predicate { $0.repasAssocieId == repasId }
        )
        for bolus in (try? contexte.fetch(descripteur)) ?? [] {
            contexte.delete(bolus)
        }
    }

    /// Recalcule les réponses glycémiques des repas depuis le CGM du hub, sans
    /// re-fetch des repas. À appeler quand de nouvelles `GlucoseReading` sont
    /// arrivées (sync HealthKit) — au démarrage, le CGM n'est pas encore
    /// synchronisé, donc les analyses seraient toutes en attente sinon.
    func rafraichirAnalyses() {
        annoterReponsesGlycemiques()
    }

    // MARK: - Privé

    private func recharger() {
        guard let contexte else { return }
        let descripteur = FetchDescriptor<Repas>(sortBy: [SortDescriptor(\.heure)])
        repas = (try? contexte.fetch(descripteur)) ?? []
        annoterReponsesGlycemiques()
    }

    /// Fenêtre au-delà de laquelle on ne calcule plus la réponse glycémique
    /// d'un repas : sans CGM aussi ancien (backfill Dexcom borné à 7 jours),
    /// l'analyse serait de toute façon `donneesManquantes`. Borne aussi le
    /// volume du fetch CGM au rechargement.
    private static let fenetreAnalyseJours = 45

    /// Calcule et pose l'`EtatAnalyse` (`@Transient`) de chaque repas récent à
    /// partir des `GlucoseReading` du hub. Un seul fetch CGM borné, puis
    /// découpage en mémoire par repas via `AssembleurReponseRepas` (pur).
    private func annoterReponsesGlycemiques() {
        defer { revisionCourbes += 1 }
        guard let contexte else { return }
        let maintenant = Date()
        let borneAnalyse = Calendar.current.date(
            byAdding: .day, value: -Self.fenetreAnalyseJours, to: maintenant
        ) ?? maintenant

        let recents = repas.filter { $0.heure >= borneAnalyse }
        guard let premier = recents.first?.heure, let dernier = recents.last?.heure else { return }

        // Fetch unique sur [T-1h du premier repas, T+4h du dernier].
        let borneBasse = premier.addingTimeInterval(AssembleurReponseRepas.debutFenetre)
        let borneHaute = dernier.addingTimeInterval(AssembleurReponseRepas.finFenetre)
        var descripteur = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.date >= borneBasse && $0.date <= borneHaute },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        descripteur.propertiesToFetch = [\.date, \.valeur]
        let echantillons = ((try? contexte.fetch(descripteur)) ?? [])
            .map { (date: $0.date, valeur: $0.valeur) }

        // Seuils du profil — « hypo » / « hors cible » doivent vouloir dire la
        // même chose ici que dans les graphes et les analyses du coucher.
        let seuils = ProfilService.shared.profil.seuilsGlycemiques

        var doseASauvegarder = false
        for unRepas in recents {
            let etat = AssembleurReponseRepas.analyser(
                heureRepas: unRepas.heure,
                aUneInjection: unRepas.aUneInjection,
                echantillons: echantillons,
                maintenant: maintenant,
                seuils: seuils
            )
            unRepas.etatAnalyse = etat

            // Persiste le verdict + ratio effectif dès qu'ils sont connus —
            // contrairement à `etatAnalyse` (transient, courbe non stockable),
            // ces deux valeurs survivent au relancement de l'app et alimentent
            // le mining R1 (CalculRatioObserve) sur tout l'historique, pas
            // seulement la fenêtre récente gardée en mémoire ici.
            guard case .disponible(let reponse) = etat else { continue }
            let doseCouvrante = unRepas.totalInsuline - (unRepas.doseCorrection ?? 0)
            let ratio = unRepas.totalGlucides > 0 && doseCouvrante > 0
                ? Double(unRepas.totalGlucides) / doseCouvrante : nil
            if unRepas.verdictPersiste != reponse.verdict
                || unRepas.ratioEffectifPersiste != ratio
                || unRepas.raisonMauvaisPersistee != reponse.raisonMauvais {
                unRepas.verdictPersiste = reponse.verdict
                unRepas.raisonMauvaisPersistee = reponse.raisonMauvais
                unRepas.ratioEffectifPersiste = ratio
                doseASauvegarder = true
            }
        }
        if doseASauvegarder { try? contexte.save() }
    }
}

// MARK: - Mapping EntreeAliment -> Aliment

extension Aliment {

    /// Mappe une entrée de saisie (`EntreeAliment`, liée à `AlimentCiqual`,
    /// quantité en grammes, dose optionnelle) vers l'`Aliment` du hub (forme
    /// déjà résolue, glucides entiers, dose non optionnelle).
    ///
    /// Choix de conversion :
    /// - `emoji` : celui de l'`AlimentCiqual`, ou 🍽 par défaut (le réf. CIQUAL
    ///   a un emoji optionnel).
    /// - `nom` : repris tel quel de l'`AlimentCiqual`.
    /// - `quantite` : grammes consommés, **arrondis** à l'entier le plus proche.
    /// - `glucides` : glucides calculés (proportionnels à la quantité),
    ///   **arrondis** à l'entier le plus proche — l'`Aliment` du hub stocke des
    ///   glucides entiers (précision suffisante, cohérente avec l'affichage).
    /// - `insuline` : `doseInsuline ?? 0` (un aliment logué pour mémoire, sans
    ///   bolus, vaut 0 u).
    @MainActor
    convenience init(depuis entree: EntreeAliment) {
        var idCiqualSource: Int?
        var codeProduitOFF: String?
        switch entree.aliment {
        case .ciqual(let a): idCiqualSource = a.id
        case .off(let p):
            codeProduitOFF = p.code.hasPrefix(EntreeAliment.prefixeCodeFige) ? nil : p.code
        }
        let taillePortion = entree.modeQuantite == .portions
            ? AlimentsRecentsService.shared.tailleDePortion(entree.aliment)
            : nil

        self.init(
            emoji: entree.emojiFige ?? entree.aliment.emoji ?? "🍽",
            nom: entree.nomFige ?? entree.aliment.nom,
            quantite: Int(entree.quantiteGrammes.rounded()),
            glucides: Int(entree.glucides.rounded()),
            insuline: entree.doseInsuline ?? 0,
            // Miniature 200 px : suffisante pour les rows du journal.
            imageURL: entree.aliment.imagePetiteURL,
            resucrage: entree.resucrage,
            idCiqualSource: idCiqualSource,
            taillePortion: taillePortion,
            codeProduitOFF: codeProduitOFF
        )
    }
}

extension EntreeAliment {

    /// Préfixe des fiches reconstruites depuis un repas enregistré : jamais un
    /// vrai code-barres.
    static let prefixeCodeFige = "repas-"

    /// Rouvre un aliment enregistré pour modification. Le hub ne garde que des
    /// valeurs figées : la fiche d'origine sert si elle redonne les glucides
    /// enregistrés (à 1 g près), sinon on reconstruit une fiche à partir
    /// d'eux — rouvrir un repas ne doit pas changer ses glucides en silence.
    init(depuis aliment: Aliment) {
        let grammes = aliment.quantite > 0 ? Double(aliment.quantite) : 100
        let reference = Self.reference(de: aliment, grammes: grammes)
        let enPortions = aliment.taillePortion != nil
            && AlimentsRecentsService.shared.tailleDePortion(reference) != nil
        self.init(
            aliment: reference,
            quantiteGrammes: grammes,
            modeQuantite: enPortions ? .portions : .grammes,
            quantiteApproximative: false,
            doseInsuline: aliment.insuline > 0 ? aliment.insuline : nil,
            note: "",
            resucrage: aliment.resucrage,
            nomFige: aliment.nom,
            emojiFige: aliment.emoji
        )
    }

    private static func reference(de aliment: Aliment, grammes: Double) -> ResultatRechercheAliment {
        func ficheFigee(code: String) -> ResultatRechercheAliment {
            .off(AlimentOFF(
                code: code, nom: aliment.nom, marque: nil, calories: nil,
                glucides: Double(aliment.glucides) * 100 / grammes,
                sucres: nil, proteines: nil, lipides: nil, fibres: nil,
                imagePetiteURL: aliment.imageURL, imageURL: aliment.imageURL
            ))
        }

        var candidate: ResultatRechercheAliment?
        if let id = aliment.idCiqualSource ?? NomsPersonnalisesService.shared.idCiqual(pourNomOrigine: aliment.nom),
           let ciqual = CiqualService.shared.aliment(id: id) {
            candidate = .ciqual(ciqual)
        } else if let code = aliment.codeProduitOFF {
            candidate = ficheFigee(code: code)
        }
        if let candidate, abs(candidate.glucides * grammes / 100 - Double(aliment.glucides)) <= 1 {
            return candidate
        }
        return ficheFigee(code: prefixeCodeFige + aliment.id.uuidString)
    }
}

// MARK: - Sections de repas (dérivation d'affichage)

/// Les 5 tranches canoniques du journal. Reste une dérivation d'affichage :
/// le hub ne stocke pas la section, seulement l'heure absolue du repas.
nonisolated enum SectionRepas: String, CaseIterable {
    case petitDejeuner
    case dejeuner
    case enCas
    case diner
    /// Fenêtre nocturne entre la fin du dîner et le début du petit-déjeuner
    /// — évite qu'un repas de milieu de nuit soit classé à tort dans
    /// « Dîner » (nearest-anchor le ferait si le dîner est tardif).
    case nuit

    /// Libellé exact attendu par `ListeRepasParSection` (mêmes chaînes).
    var titre: String {
        switch self {
        case .petitDejeuner: return "Petit déjeuner"
        case .dejeuner:      return "Déjeuner"
        case .enCas:         return "En-cas"
        case .diner:         return "Dîner"
        case .nuit:          return "Nuit"
        }
    }

    /// Délai après le **début** du dîner marquant le passage à la section
    /// « Nuit » — fixe (pas un réglage utilisateur séparé), pour ne pas
    /// ajouter un 5ᵉ champ dans les réglages horaires du profil.
    private static let delaiNuitApresDinerMinutes = 180 // 3h

    /// Classe une heure de repas dans une section selon les **heures de
    /// début du profil** (`HorairesRepas`) : chaque horaire marque le
    /// **début** de sa section (pas un point de référence le plus proche),
    /// la section retenue est celle dont le début est le dernier atteint
    /// avant l'heure du repas — journée traitée en cercle (24h), donc le
    /// passage minuit est géré sans cas particulier. Le goûter du profil
    /// correspond à la section « En-cas » ; « Nuit » démarre automatiquement
    /// `delaiNuitApresDinerMinutes` après le début du dîner.
    init(heure: Date, horaires: HorairesRepas) {
        let cal = Calendar.current
        func minuteDuJour(_ date: Date) -> Int {
            let c = cal.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        let cible = minuteDuJour(heure)
        let debutDiner = minuteDuJour(horaires.diner)
        let debutNuit = (debutDiner + Self.delaiNuitApresDinerMinutes) % (24 * 60)

        let bornes: [(section: SectionRepas, debut: Int)] = [
            (.petitDejeuner, minuteDuJour(horaires.petitDejeuner)),
            (.dejeuner,      minuteDuJour(horaires.dejeuner)),
            (.enCas,         minuteDuJour(horaires.gouter)),
            (.diner,         debutDiner),
            (.nuit,          debutNuit),
        ]
        self = Self.section(pour: cible, bornes: bornes)
    }

    /// Trouve la section dont le début est le **dernier atteint avant**
    /// `cible`, bornes traitées de façon circulaire (24h). Si `cible` est
    /// avant toutes les bornes du jour (ex. 00h30 alors que la plus petite
    /// borne est à 01h), la section active est celle qui a commencé la
    /// veille — la dernière borne une fois triées.
    private static func section(
        pour cible: Int,
        bornes: [(section: SectionRepas, debut: Int)]
    ) -> SectionRepas {
        let triees = bornes.sorted { $0.debut < $1.debut }
        if let trouvee = triees.last(where: { $0.debut <= cible }) {
            return trouvee.section
        }
        return triees.last?.section ?? .petitDejeuner
    }
}

#if DEBUG
extension RepasService {

    /// Container in-memory peuplé pour les `#Preview` — remplace l'ancien jeu
    /// mock du journal. Hors `DEBUG`, l'app démarre sur un hub vide
    /// (dégradation gracieuse → état vide honnête).
    @MainActor
    static var conteneurApercu: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Repas.self, configurations: config)
        for unRepas in echantillonsApercu() {
            container.mainContext.insert(unRepas)
        }
        return container
    }

    /// Instance de service **démarrée** sur un container de démo — pour les
    /// previews qui consomment `RepasService` via `@Environment`.
    @MainActor
    static func apercu() -> RepasService {
        let service = RepasService()
        service.demarrer(contexte: conteneurApercu.mainContext)
        return service
    }

    /// Jeu de repas de démonstration sur la journée courante (un par section).
    /// Uniquement pour previews / captures. `etatAnalyse` laissé à `nil`
    /// (dérivation non persistée, pas d'assembleur CGM branché).
    static func echantillonsApercu() -> [Repas] {
        let cal = Calendar.current
        func aujourdhui(_ h: Int, _ m: Int = 0) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
        }

        return [
            Repas(
                heure: aujourdhui(7, 30),
                aliments: [
                    Aliment(emoji: "🥣", nom: "Flocons d'avoine", quantite: 80, glucides: 54, insuline: 3.0),
                    Aliment(emoji: "🍌", nom: "Banane", quantite: 120, glucides: 27, insuline: 1.5),
                ]
            ),
            Repas(
                heure: aujourdhui(12, 30),
                aliments: [
                    Aliment(emoji: "🍝", nom: "Pâtes complètes", quantite: 90, glucides: 60, insuline: 3.5),
                    Aliment(emoji: "🥦", nom: "Brocolis vapeur", quantite: 200, glucides: 8, insuline: 0.0),
                ]
            ),
            Repas(
                heure: aujourdhui(16, 0),
                aliments: [
                    Aliment(emoji: "🍪", nom: "Cookie", quantite: 30, glucides: 18, insuline: 0.0),
                ]
            ),
            Repas(
                heure: aujourdhui(19, 45),
                aliments: [
                    Aliment(emoji: "🍚", nom: "Riz basmati", quantite: 70, glucides: 56, insuline: 3.0),
                    Aliment(emoji: "🐟", nom: "Saumon grillé", quantite: 130, glucides: 0, insuline: 0.0),
                ]
            ),
        ]
    }

    /// Historique synthétique dédié au mining R1 (`CalculRatioObserve`), placé
    /// **au-delà** de `fenetreAnalyseJours` (45 jours) — hors de cette fenêtre,
    /// `annoterReponsesGlycemiques()` ne recalcule jamais le verdict d'un repas
    /// depuis le CGM, donc le `verdictPersiste` posé ici à la construction
    /// reste stable (la courbe CGM synthétique du preview ne matcherait de
    /// toute façon aucun repas précis). Objectif : illustrer tous les états
    /// possibles de la carte de progression / de la sheet « Écart de ratio »
    /// sans dépendre d'un vrai calcul CGM — chaque tranche est peuplée
    /// directement avec le verdict voulu, en réutilisant les mêmes constantes
    /// (`effectifMinimalBucket`, `toleranceRatio`) que `CalculRatioObserve`
    /// pour rester cohérent si elles changent.
    ///
    /// - Déjeuner : écart net (les repas sous-dosés marchent mieux — ratio
    ///   actuel probablement trop fort).
    /// - Petit-déjeuner : bien calibré, pas d'écart.
    /// - Goûter : tranches trop peu fournies, taux brut seulement.
    /// - Dîner : volontairement pas touché, reste sur le seul repas du jour
    ///   (`echantillonsApercu()`) pour illustrer l'état quasi vide.
    static func echantillonsApercuR1() -> [Repas] {
        let cal = Calendar.current

        func repasType(joursAvant: Int, heure: (h: Int, m: Int), glucides: Int, dose: Double, verdict: VerdictGlycemique) -> Repas {
            let jour = cal.date(byAdding: .day, value: -joursAvant, to: Date()) ?? Date()
            let date = cal.date(bySettingHour: heure.h, minute: heure.m, second: 0, of: jour) ?? jour
            return Repas(
                heure: date,
                aliments: [Aliment(emoji: "🍽", nom: "Repas type", quantite: 1, glucides: glucides, insuline: 0)],
                doseGlobale: dose,
                verdictPersiste: verdict,
                ratioEffectifPersiste: Double(glucides) / dose
            )
        }

        /// Génère un lot réparti en 3 tranches (faible / proche / forte du
        /// ratio configuré), chacune avec le nombre de bons verdicts demandé
        /// — les non-bons alternent moyen/mauvais. Le ratio varie sur toute
        /// la plage de la tranche (pas une valeur fixe) : sinon tous les
        /// repas d'une tranche tombent au même x et s'empilent en une seule
        /// colonne sur le graphique — même plages que les autres previews
        /// de la page (`GraphiqueGelulesRatio`/`PageEcartRatio`).
        func lot(
            departJours: Int, glucides: Int, doseSuggeree: Double, heure: (h: Int, m: Int),
            faible: (bon: Int, total: Int), proche: (bon: Int, total: Int), forte: (bon: Int, total: Int)
        ) -> [Repas] {
            var jour = departJours
            var resultat: [Repas] = []
            func ajouter(_ compte: (bon: Int, total: Int), plage: ClosedRange<Double>) {
                for i in 0..<compte.total {
                    let ratio = plage.lowerBound + (plage.upperBound - plage.lowerBound) * Double(i) / Double(max(1, compte.total - 1))
                    let verdict: VerdictGlycemique = i < compte.bon ? .bon : (i.isMultiple(of: 2) ? .moyen : .mauvais)
                    resultat.append(repasType(joursAvant: jour, heure: heure, glucides: glucides, dose: doseSuggeree * ratio, verdict: verdict))
                    jour += 1
                }
            }
            ajouter(faible, plage: 0.55...0.78)
            ajouter(proche, plage: 0.85...1.15)
            ajouter(forte, plage: 1.22...1.55)
            return resultat
        }

        let dejeuner = lot(
            departJours: 50, glucides: 100, doseSuggeree: 100.0 / 12, heure: (12, 30),
            faible: (8, 10), proche: (7, 15), forte: (2, 10)
        )
        let petitDejeuner = lot(
            departJours: 90, glucides: 50, doseSuggeree: 50.0 / 8, heure: (7, 30),
            faible: (3, 6), proche: (14, 20), forte: (3, 6)
        )
        let gouter = lot(
            departJours: 130, glucides: 40, doseSuggeree: 40.0 / 15, heure: (16, 30),
            faible: (2, 4), proche: (7, 10), forte: (1, 3)
        )

        return dejeuner + petitDejeuner + gouter
    }
}
#endif
