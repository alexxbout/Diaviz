# CloudKit — Sync iCloud
>   Le hub SwiftData synchronise via CloudKit (backup + multi-appareils). Ce doc rassemble les contraintes de schéma et les pièges de fiabilité découverts **à l'exécution** — aucun n'est une erreur de compilation, tous se manifestent par des données qui disparaissent, réapparaissent ou s'écrasent silencieusement.  

**Statut** : 🟢 Livré et vérifié sur device (commits `6c9267a` puis `ae5baaa`, 17 août 2026). Capability iCloud + Background Modes activées, sync fonctionnelle, restauration après réinstallation testée.

---

## Périmètre : tout ce que produit l'utilisateur est dans le hub
Le hub SwiftData contient **14** `**@Model**` : les faits horodatés (`GlucoseReading`, `Injection`, `Repas`, `Aliment`, `ActiviteSportive`, `EtatDeclare`, `Medicament`, `PeriodePause`, `Resucrage`), le **profil** (`ProfilUtilisateur`) et les **préférences d'usage** (`PreferenceAlimentCiqual`, `AlimentRecentEnregistre`, `ContexteNormaliseEnregistre`, `RepasARevoirMasque`).

Profil et préférences vivaient auparavant en `UserDefaults` : perdus à chaque désinstallation, jamais synchronisés. C'était invisible tant qu'on ne réinstallait pas — puis l'utilisateur retrouvait une app vide de ses renommages d'aliments, de ses quantités habituelles, de sa configuration entière.

**Règle** : `UserDefaults` ne garde que ce qui est propre à l'appareil et n'a aucun sens ailleurs (ancre de requête HealthKit, session sportive en cours, drapeaux de démarrage). **Jamais une donnée saisie par l'utilisateur.**

---

## Les contraintes CloudKit du schéma
SwiftData + CloudKit utilise `NSPersistentCloudKitContainer` sous le capot — les règles viennent de Core Data. Aucune n'est vérifiée à la compilation : le crash arrive au lancement.

### 1. Aucun `@Attribute(.unique)` 
CloudKit ne supporte pas les contraintes unique. `GlucoseReading.date` la portait (dédup à l'ingestion). Retirée sans impact réel : `HealthKitCGMService.datesExistantes()` fait déjà la dédup **côté app** (fetch + filtre avant insert), la contrainte DB n'était pas le mécanisme réellement utilisé.

### 2. Toute propriété stockée optionnelle ou pourvue d'un défaut
Défauts neutres (`0`, `""`, `Date.distantPast`, premier cas d'enum) — **jamais exercés en pratique**, tous les `init()` gardent leurs paramètres obligatoires. Pur filet de secours pour la récupération partielle de sync (un objet peut arriver avant sa relation).

### 3. Relations : inverse déclaré ET stockage optionnel
Les 3 relations vers `Aliment` (`Repas.aliments`, `Resucrage.aliments`, `ActiviteSportive.alimentsPreSport`) n'avaient pas d'inverse → premier crash (« all relationships have an inverse »). Ajout de `repasParent`, `resucrageParent`, `activiteSportiveParent` sur `Aliment`.

Une fois l'inverse ajouté, deuxième crash (« all relationships be optional ») — même une relation à plusieurs doit être **typée optionnelle** côté stockage :

```swift
// Stockage réel — optionnel, jamais lu directement hors de ce fichier.
@Relationship(deleteRule: .cascade, inverse: \Aliment.repasParent)
var _aliments: [Aliment]? = []

// Vue publique non-optionnelle — même nom qu'avant, zéro impact appelants.
var aliments: [Aliment] {
    get { _aliments ?? [] }
    set { _aliments = newValue }
}
```
### 4. Les structs `Codable` imbriquées aussi
Découvert sur `ProfilUtilisateur` : une propriété de type struct custom non optionnelle plante au cast à l'ouverture du store (« Could not cast value of type 'Swift.Optional' to 'Diaviz.PreferencesAvancees' »), **même avec une valeur par défaut**. Contrairement aux types natifs Core Data (Date, UUID, enum brut), il leur faut une vraie optionalité.

Même pattern que ci-dessus : `_ratiosParMoment` / `ratiosParMoment`, `_horairesRepas` / `horairesRepas`, `_seuilsGlycemiques`, `_preferencesAvancees`, `_variantes` sur `ContexteNormaliseEnregistre`.

---

## ⚠️ Piège : parent unique par `Aliment` 
Une fois l'inverse déclaré, SwiftData impose **un seul parent à la fois** par `Aliment` — **même hors** `**ModelContext**`, y compris pour un objet construit à la main dans un test. Réutiliser la **même instance** dans plusieurs `Repas` la réassigne silencieusement au **dernier** constructeur : les `Repas` précédents se retrouvent avec `.aliments` vide, sans erreur ni warning.

`CalculRepasARevoirTests.swift` faisait exactement ça (16 échecs). Corrigé en construisant un `aliment(...)` frais par `Repas` — ce qui reflète d'ailleurs la vraie donnée : deux repas identiques ont chacun leurs propres lignes `Aliment` en production.

**Leçon** : ne jamais partager une instance d'objet enfant entre plusieurs parents, même dans un test, dès qu'un inverse est déclaré.

---

## ⚠️ Piège : `delete(model:)` n'est pas exporté vers CloudKit
`ModelContext.delete(model:)` est un **batch delete** : il vide le store local mais contourne le contexte, donc ne génère aucun historique de transaction et `NSPersistentCloudKitContainer` n'a rien à exporter.

Symptôme observé : l'utilisateur supprime ses données, ferme l'app, la rouvre — **tout est revenu**, ré-importé depuis un iCloud qui n'a jamais vu la suppression.

**Toujours supprimer objet par objet** via le contexte (`SuppressionDonneesService`). Plus lent, mais c'est la seule forme que CloudKit propage.

---

## ⚠️ Piège : ne jamais écraser un profil en cours de saisie
`ProfilService` ré-adopte la ligne profil canonique à chaque import CloudKit. Sans garde-fou, cela remplaçait l'objet **pendant que l'utilisateur remplissait l'onboarding** : ses saisies étaient substituées par celles de la sauvegarde au moment de valider.

`adopterMeilleureLigne()` ne remplace désormais le profil courant que s'il est un **brouillon intact** (jamais renseigné). Dès la première frappe, il est à l'utilisateur.

Corollaire : `demarrer(contexte:)` **n'insère aucune ligne** quand le store est vide. Une ligne vide créée au lancement (a) partirait elle-même sur iCloud, (b) porterait une date du jour et gagnerait tout départage par date contre le vrai profil arrivé quelques secondes plus tard. Le profil n'est matérialisé qu'à la première vraie saisie.

Le départage entre lignes multiples fait **gagner un profil valide contre un brouillon vide**, quelle que soit la date.

---

## Détection au premier lancement : interroger le serveur, pas attendre un événement
Après une réinstallation, il faut savoir si le compte contient déjà des données pour proposer une restauration plutôt qu'un onboarding vierge.

**Ce qui ne marche pas** : attendre le premier événement `.import` réussi. CloudKit en émet un dès la mise en place du store, souvent **vide** — on concluait « rien sur iCloud » en 1-2 secondes, puis les vraies données arrivaient pendant l'onboarding.

**Ce qui marche** : demander directement à CloudKit si la zone `com.apple.coredata.cloudkit.zone` existe (`SyncICloudService.interrogerDonneesICloud()`). Réponse immédiate et sans ambiguïté.

Trois issues, dont une essentielle : si le compte est **injoignable** (réseau, iCloud désactivé), ne surtout pas conclure « vide » — conclure sur une panne réseau condamnerait définitivement des données bien réelles. On laisse l'utilisateur avancer sans marquer la question résolue, elle est rejouée au lancement suivant.

Rappel confirmé par Apple DTS : **aucune API ne permet de forcer une synchronisation** ni de savoir ce qui reste en attente d'envoi.

---

## Container & configuration
`DiavizApp.swift` — container explicite (le raccourci `.modelContainer(for:)` ne permet pas de choisir `cloudKitDatabase`) :

```swift
let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
let container = try ModelContainer(for: schema, configurations: [configuration])
```
`.automatic` réutilise le container iCloud déclaré dans les entitlements sans dupliquer l'identifiant en dur.

`Diaviz.entitlements` :

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.fr.al3xdre.diaviz</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
```
**Background Modes → Remote notifications : obligatoire**, contrairement à ce qu'on pensait d'abord. CloudKit refuse de démarrer sans (« BUG IN CLIENT OF CLOUDKIT: CloudKit push notifications require the 'remote-notification' background mode »). À activer **via Xcode → cible Diaviz → Signing & Capabilities → + Capability → Background Modes** : la clé `UIBackgroundModes` est réservée aux capabilities cochées à la main, l'ajouter en `INFOPLIST_KEY_*` dans les build settings reste sans effet.

---

## Interface utilisateur (Réglages → Données)
- **État de synchronisation** : activité en cours, dernier envoi, dernière réception, **et les erreurs**. Une version antérieure filtrait sur `event.succeeded`  : un export en échec ne laissait aucune trace, indiscernable d'un « rien à envoyer ».
- **Compteurs par type** — reflet direct de ce que l'import a descendu, utile après réinstallation.
- **Archive JSON** (`ArchiveDonneesService`  ) : export/import complet, partagé hors de l'app. Filet indépendant de CloudKit — la sync protège de la perte d'appareil, pas d'une suppression accidentelle (qui se propage, elle aussi).
- **Deux suppressions seulement** : « Effacer mon historique » (données saisies) et « Tout réinitialiser » (tout, local + zone CloudKit supprimée directement). Une troisième option existait, sa distinction avec les autres était devenue fausse une fois les suppressions correctement propagées.
Note : « Supprimer les données de l'app » dans les **Réglages iOS** reste souvent sans effet visible ici — un build Xcode utilise l'environnement CloudKit **Development**, séparé de Production.
---

## Vérifications
Build Debug ✅ · Build Release ✅ · 261/261 tests ✅ · testé sur device réel (CloudKit ne fonctionne pas en simulateur).

Aucun `#Predicate` ne filtre sur les relations concernées (limitation connue : les predicates sur relation à plusieurs optionnelle plantent avec « to-many key not allowed here » — à surveiller si un futur predicate touche `aliments` / `alimentsPreSport`).


