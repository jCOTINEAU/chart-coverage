# Helm Coverage POC

POC pour mesurer le **coverage des branches de templates Helm** (structures `{{ if }}`, `{{ with }}`, `{{ range }}`).

## Principe

1. **Instrumentation** : Injection automatique de marqueurs dans les templates
   - Header : `# COV:TOTAL:<fichier>:<count>`
   - Branches : `# COV:<fichier>:<id>`

2. **Génération** : `helm template` avec values spécifiques

3. **Mesure** : Comptage des marqueurs présents vs total

## Usage

```bash
# Coverage avec values par défaut
./helm-coverage.sh <chart-path>

# Coverage avec un fichier values
./helm-coverage.sh <chart-path> <values-file>

# Coverage avec plusieurs fichiers values (union)
./helm-coverage.sh <chart-path> <values-file1> <values-file2> [...]
```

Le script fonctionne avec des **chemins relatifs ou absolus** vers le chart.

Lorsque plusieurs fichiers values sont fournis, le script calcule le **coverage final** comme l'**union** de toutes les branches couvertes par au moins un des fichiers.

## Exemples

```bash
# Depuis le répertoire du script
cd ~/workspace/debug/chart-code-coverage
./helm-coverage.sh test-chart
./helm-coverage.sh test-chart test-chart/values.yaml
./helm-coverage.sh test-chart test-chart/values-full.yaml

# Coverage combiné avec plusieurs fichiers values
./helm-coverage.sh test-chart test-chart/values.yaml test-chart/values-full.yaml

# Avec un chemin absolu (depuis n'importe où)
~/workspace/debug/chart-code-coverage/helm-coverage.sh /path/to/my-chart

# Avec un chemin relatif
cd /path/to/
~/workspace/debug/chart-code-coverage/helm-coverage.sh ./my-chart
```

## Output

### Avec un seul fichier values

```
📊 Calcul du coverage par values file...
========================================

📄 Values: values.yaml
  ❌ Coverage: 1/3 branches (33%)

========================================
📊 Coverage final (union de tous les tests)...

❌ deployment.yaml                  0/  1 (  0%)
❌ ingress.yaml                     0/  1 (  0%)
✅ service.yaml                     1/  1 (100%)

========================================
❌ TOTAL: 1/3 branches (33%)
```

### Avec plusieurs fichiers values

```
📊 Calcul du coverage par values file...
========================================

📄 Values: values.yaml
  ❌ Coverage: 1/3 branches (33%)

📄 Values: values-full.yaml
  ✅ Coverage: 3/3 branches (100%)

========================================
📊 Coverage final (union de tous les tests)...

✅ deployment.yaml                  1/  1 (100%)
✅ ingress.yaml                     1/  1 (100%)
✅ service.yaml                     1/  1 (100%)

========================================
✅ TOTAL: 3/3 branches (100%)
```

## Limitations

- ✅ Trace les structures : `{{ if }}`, `{{ with }}`, `{{ range }}`
- ❌ N'analyse pas les helpers internes (`_helpers.tpl`)
- ❌ Ne trace pas les fonctions inline (`{{ include }}`, `{{ default }}`)
- ✅ Coverage partiel mais **quantifiable**

## Stratégie de test

1. Créer plusieurs fichiers values pour couvrir tous les cas
2. Exécuter le script avec tous les fichiers values
3. Le script calcule automatiquement le coverage combiné

```bash
# Ancienne méthode (un fichier à la fois)
./helm-coverage.sh my-chart values/minimal.yaml    # → 40%
./helm-coverage.sh my-chart values/with-ingress.yaml # → 60%
./helm-coverage.sh my-chart values/full.yaml       # → 100% ✅

# Nouvelle méthode (union automatique)
./helm-coverage.sh my-chart values/minimal.yaml values/with-ingress.yaml values/full.yaml
# → Affiche le coverage de chaque fichier + coverage final (union)
```

Le coverage final représente l'**union** de toutes les branches couvertes par au moins un des fichiers values.

