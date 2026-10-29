# Guide de déploiement Fast-Cash sur Render

Ce guide explique comment mettre l’API Fast-Cash en ligne sur [Render](https://render.com) et la brancher aux applications Android (client et vendeur PDR).

## Ce qui est déjà préparé dans le projet

| Fichier | Rôle |
|--------|------|
| `render.yaml` | Blueprint Render (Web Service Python) |
| `backend/run_all.py` | Démarre les microservices ; le gateway écoute sur `0.0.0.0:$PORT` |
| `backend/runtime.txt` | Version Python (3.12) |
| `mobile/scripts/run_render.ps1` | Lance l’app Android contre l’URL Render |
| `mobile/scripts/build_render.ps1` | Build l’APK avec l’URL Render |
| `mobile/api_base.local.example` | Modèle pour l’URL HTTPS de l’API |

Architecture : un seul service public (gateway HTTPS). Les microservices (identité, PDR, opérations, notifications, admin) restent en local sur le même serveur.

```
Téléphone Android  --HTTPS-->  gateway Render ($PORT)
                                    |
                    +---------------+---------------+
                    |   8001   8002   8003   8004   8005
                 identity   pdr  operations notif  admin
                                    |
                              SQLite (backend/data)
```

---

## Étape 1 — Compte Render et GitHub

1. Crée un compte sur [https://render.com](https://render.com) (connexion GitHub recommandée).
2. Crée un dépôt GitHub pour Fast-Cash (privé recommandé).
3. Depuis `c:\Fast_Cash`, pousse le code :

```powershell
cd c:\Fast_Cash
git add .
git commit -m "Préparer Fast-Cash pour Render"
git branch -M main
git remote add origin https://github.com/VOTRE-COMPTE/VOTRE-REPO.git
git push -u origin main
```

Remplace `VOTRE-COMPTE` et `VOTRE-REPO` par tes vrais noms. Si le remote existe déjà, utilise seulement `git push -u origin main`.

---

## Étape 2 — Créer le Web Service sur Render

### Option A — Blueprint (recommandé)

1. Dashboard Render → **New** → **Blueprint**.
2. Connecte le dépôt GitHub Fast-Cash.
3. Render lit `render.yaml` à la racine.
4. Valide la création du service `fast-cash-api`.
5. Attends la fin du premier deploy (logs : Build → Deploy).

### Option B — Web Service manuel

1. **New** → **Web Service**.
2. Branche le même dépôt GitHub.
3. Réglages :

| Champ | Valeur |
|-------|--------|
| Name | `fast-cash-api` (ou autre) |
| Region | Frankfurt (ou la plus proche) |
| Runtime | Python |
| Root Directory | `backend` |
| Build Command | `pip install -r requirements.txt` |
| Start Command | `python run_all.py` |
| Instance type | Free (démo) ou Starter (plus stable) |
| Health Check Path | `/api/health` |

4. Clique **Create Web Service** et attends le deploy.

---

## Étape 3 — Vérifier que l’API répond

1. Dans Render, ouvre ton service → copie l’URL du type :

   `https://fast-cash-api-xxxx.onrender.com`

2. Dans le navigateur, ouvre :

   `https://fast-cash-api-xxxx.onrender.com/api/health`

3. Tu dois voir quelque chose comme :

```json
{
  "gateway": true,
  "services": {
    "identity": true,
    "pdr": true,
    "operations": true,
    "notifications": true,
    "admin": true
  }
}
```

4. Test rapide de la page d’accueil : `https://…onrender.com/`  
   → doit afficher le nom Fast-Cash.

Si le health check échoue : regarde **Logs** sur Render (souvent un service interne qui met trop longtemps à démarrer, ou une erreur Python au boot).

---

## Étape 4 — Brancher les applications Android

L’URL doit être en **HTTPS** (sans `/` à la fin).

### Configurer l’URL

```powershell
cd c:\Fast_Cash\mobile
copy api_base.local.example api_base.local
notepad api_base.local
```

Contenu de `api_base.local` (exemple) :

```
https://fast-cash-api-xxxx.onrender.com
```

Ce fichier est ignoré par Git (ne sera pas poussé).

### Lancer en debug sur téléphone / émulateur

```powershell
cd c:\Fast_Cash\mobile
.\scripts\run_render.ps1
```

Ou avec un appareil précis :

```powershell
.\scripts\run_render.ps1 -Device emulator-5554
```

### Builder l’APK à installer

```powershell
cd c:\Fast_Cash\mobile
.\scripts\build_render.ps1
```

APK généré :

`mobile\build\app\outputs\flutter-apk\app-release.apk`

Installe-le sur le téléphone. Client et vendeur utilisent **la même APK** ; le rôle dépend du numéro de connexion (OTP).

### Alternative sans script

```powershell
flutter run --dart-define=API_BASE=https://fast-cash-api-xxxx.onrender.com
flutter build apk --dart-define=API_BASE=https://fast-cash-api-xxxx.onrender.com
```

---

## Étape 5 — Comptes de test après déploiement

Les comptes seed (si la base est neuve) restent ceux du `README.md` :

| Rôle | Identifiant |
|------|-------------|
| Client | `+243 810 123 456` |
| Vendeur PDR | `+243 815 000 001` |
| Admin web | `admin@fastcash.cd` / `FastCash-2026` |

Le code OTP s’affiche à l’écran de l’app et dans les **Logs** Render (pas de SMS réel).

---

## Étape 6 — Mise à jour de l’application (popup)

Quand tu publies un nouvel APK :

1. Héberge l’APK (lien HTTPS public).
2. Connecte-toi à l’admin web (si déployé) ou mets à jour les settings via l’API admin.
3. Dans **Paramètres** :
   - **Version publiée** = version du nouvel APK (ex. `1.0.1`)
   - **Version minimale** = optionnel (force la mise à jour si l’ancienne est trop basse)
   - **Lien de téléchargement** = URL de l’APK
4. Au prochain lancement, les utilisateurs voient la popup « Mise à jour disponible ».

---

## Points d’attention (plan Free)

| Sujet | Comportement |
|-------|----------------|
| Sleep | Après ~15 min sans trafic, le service s’endort. Le premier appel peut prendre 30–60 s. |
| Données | SQLite est sur le disque éphémère : **redéploiement = base remise à zéro** (sauf Persistent Disk payant). |
| Mémoire | 6 processus Python : sur Free, surveille les logs si le service redémarre souvent. |
| Stabilité | Pour une démo client, préfère le plan **Starter** + **Persistent Disk** monté sur le dossier `data` du backend. |

### Persistent Disk (optionnel, plan payant)

1. Sur le Web Service → **Disks** → ajoute un disque.
2. Mount path typique : `/opt/render/project/src/data`  
   (à ajuster selon le chemin réel du service ; l’app écrit dans `backend/data/fastcash.db` relatif au `rootDir` `backend`, donc souvent un mount sur `data` à la racine du service backend).
3. Redéploie après montage.

---

## Checklist finale

- [ ] Code poussé sur GitHub  
- [ ] Web Service Render créé et deploy **Live**  
- [ ] `/api/health` → tous les services à `true`  
- [ ] `mobile/api_base.local` renseigné avec l’URL HTTPS  
- [ ] App lancée ou APK installé avec cette URL  
- [ ] Connexion OTP client ou PDR OK  

---

## Dépannage rapide

| Symptôme | Piste |
|----------|--------|
| `Impossible de joindre le serveur` | URL incorrecte, service endormi (réveille avec `/api/health`), ou APK buildé sans `API_BASE` |
| Health check rouge | Lire les Logs Render ; vérifier `python run_all.py` et le démarrage des ports 8001–8005 |
| OTP introuvable | Regarder les Logs Render au moment de la demande OTP |
| Données disparues | Normal sur Free après redeploy ; utiliser un Persistent Disk |
| Popup mise à jour n’apparaît pas | Version publiée ≤ version installée, ou lien de téléchargement vide |

---

## Suite possible (hors ce guide)

- Déployer le **frontend admin** (`frontend/`) en Static Site Render pointant vers la même API.
- Migrer SQLite → PostgreSQL Render pour une prod multi-instances.
