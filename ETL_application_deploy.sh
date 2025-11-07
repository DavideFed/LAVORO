#!/bin/bash

# ============================================
# SCRIPT DI DEPLOY PER APPLICATION_*.SH
# ============================================
# Gestisce il deploy della metodologia Application_*.sh + XML + CTL
# con esecuzione in /GFS/infa/infa_shared/IDD e monitoraggio log
# ============================================

# Configurazione
INFA_USER="infa"
INFA_GROUP="infa"

# Configurazione cartella condivisa
SHARED_BASE_DIR="/GFS/infa/infa_shared"
DEPLOY_DIR="$SHARED_BASE_DIR/IDD"

# Definizione della directory di lavoro ETL (specifica per questo rilascio)
dir2="${p:set-folders/environmentEtlFolder}"
etl_path="$dir2"

# Salva il path assoluto della directory ETL all'inizio
etl_path_abs=$(cd "$etl_path" && pwd)

# Array per tenere traccia dei PID delle tail
declare -a TAIL_PIDS=()

# ============================================
# FUNZIONI
# ============================================

# Funzione per creare le directory condivise
create_shared_directories() {
    echo ""
    echo "=== Creazione directory condivise ==="
   
    # Crea la directory base se non esiste
    if [ ! -d "$SHARED_BASE_DIR" ]; then
        echo "Creazione directory base: $SHARED_BASE_DIR"
        mkdir -p "$SHARED_BASE_DIR"
    fi
   
    # Crea la directory IDD
    if [ ! -d "$DEPLOY_DIR" ]; then
        echo "Creazione directory deploy: $DEPLOY_DIR"
        mkdir -p "$DEPLOY_DIR"
    fi
   
    # Imposta i permessi per l'accesso condiviso
    echo "Impostazione permessi per accesso condiviso..."
    chmod -R 755 "$DEPLOY_DIR"
    chown -R $INFA_USER:$INFA_GROUP "$DEPLOY_DIR"
   
    echo "Directory condivise create e configurate correttamente"
}

# Funzione per copiare i file nella directory condivisa
copy_files_to_shared() {
    echo ""
    echo "=== Copia file nella directory condivisa ==="
   
    # Naviga nella directory ETL usando il path assoluto
    cd "$etl_path_abs" || exit 1
   
    # Conta i file copiati
    files_copied=0
   
    # Copia i file Application_*.sh
    echo "Copia file Application_*.sh..."
    for file in Application_*.sh; do
        if [ -f "$file" ]; then
            echo "  Copiando: $file -> $DEPLOY_DIR/"
            cp "$file" "$DEPLOY_DIR/"
            chmod 755 "$DEPLOY_DIR/$file"
            chown $INFA_USER:$INFA_GROUP "$DEPLOY_DIR/$file"
            files_copied=$((files_copied + 1))
        fi
    done
   
    # Copia i file XML
    echo "Copia file XML..."
    for file in *.xml; do
        if [ -f "$file" ]; then
            echo "  Copiando: $file -> $DEPLOY_DIR/"
            cp "$file" "$DEPLOY_DIR/"
            chmod 755 "$DEPLOY_DIR/$file"
            chown $INFA_USER:$INFA_GROUP "$DEPLOY_DIR/$file"
            files_copied=$((files_copied + 1))
        fi
    done
   
    # Copia i file CTL (se presenti)
    echo "Copia file CTL (se presenti)..."
    ctl_found=0
    for file in *.ctl; do
        if [ -f "$file" ]; then
            echo "  Copiando: $file -> $DEPLOY_DIR/"
            cp "$file" "$DEPLOY_DIR/"
            chmod 755 "$DEPLOY_DIR/$file"
            chown $INFA_USER:$INFA_GROUP "$DEPLOY_DIR/$file"
            files_copied=$((files_copied + 1))
            ctl_found=1
        fi
    done
   
    if [ $ctl_found -eq 0 ]; then
        echo "  Nessun file CTL trovato (opzionale)"
    fi
   
    echo "Totale file copiati: $files_copied"
}

# Funzione per impostare i permessi sulla working directory
set_permissions() {
    echo ""
    echo "=== Impostazione permessi sulla working directory ==="
   
    # Naviga nella directory ETL
    cd "$etl_path_abs" || exit 1
   
    # Aggiungi permessi di traversal sulle directory madri
    DIR="$(pwd)"
    IFS='/' read -ra PARTS <<< "$DIR"
    CURRENT="/"
   
    for part in "${PARTS[@]}"; do
        [[ -z "$part" ]] && continue
        CURRENT="$CURRENT$part"
       
        if ! getfacl -p "$CURRENT" 2>/dev/null | grep -q "^user:$INFA_USER:.*x"; then
            setfacl -m "u:$INFA_USER:--x" "$CURRENT" 2>/dev/null || true
        fi
       
        CURRENT="$CURRENT/"
    done
   
    # Assegna permessi rwx su directory
    find . -type d -exec setfacl -m "u:$INFA_USER:rwx" {} + 2>/dev/null || true
   
    # Assegna permessi rw su file
    find . -type f -exec setfacl -m "u:$INFA_USER:rw-" {} + 2>/dev/null || true
   
    # Imposta ACL mask
    find . \( -type f -o -type d \) -exec setfacl -m "m::rwx" {} + 2>/dev/null || true
   
    echo "Permessi impostati correttamente"
}

# Funzione per killare solo le tail di questo rilascio
cleanup_tail_processes() {
    echo ""
    echo "=== Terminazione processi tail di questo rilascio ==="
   
    if [ ${#TAIL_PIDS[@]} -eq 0 ]; then
        echo "Nessun processo tail da terminare"
        return
    fi
   
    for pid in "${TAIL_PIDS[@]}"; do
        if ps -p $pid > /dev/null 2>&1; then
            kill $pid 2>/dev/null
            echo "Terminato tail con PID: $pid"
        fi
    done
   
    echo "Terminati ${#TAIL_PIDS[@]} processi tail"
}

# ============================================
# MAIN EXECUTION
# ============================================

echo ""
echo "=========================================="
echo "DEPLOY APPLICATION_*.SH"
echo "=========================================="
echo ""

# FASE 0: PREPARAZIONE DIRECTORY CONDIVISE
echo "=== FASE 0: Preparazione directory condivise ==="
create_shared_directories

# FASE 1: VERIFICA DIRECTORY DI LAVORO
echo ""
echo "=== FASE 1: Verifica directory di lavoro ==="

# Verifica che la directory ETL esista
if [ ! -d "$etl_path_abs" ]; then
    echo "ERRORE: Directory $etl_path_abs non trovata"
    exit 1
fi

echo "Directory di lavoro (specifica per questo rilascio): $etl_path_abs"

# FASE 2: COPIA FILE NELLA DIRECTORY CONDIVISA
echo ""
echo "=== FASE 2: Copia file nella directory condivisa ==="
copy_files_to_shared

# FASE 3: IMPOSTAZIONE PERMESSI
echo ""
echo "=== FASE 3: Impostazione permessi ==="
set_permissions

# FASE 4: ESECUZIONE SCRIPT APPLICATION
echo ""
echo "=== FASE 4: Esecuzione script Application ==="
echo ""

# Naviga nella directory ETL per identificare i file da eseguire
cd "$etl_path_abs" || exit 1

# Conta gli script da eseguire
scripts_count=0
for sh_file in Application_*.sh; do
    if [ -f "$sh_file" ]; then
        scripts_count=$((scripts_count + 1))
    fi
done

if [ $scripts_count -eq 0 ]; then
    echo "ERRORE: Nessuno script Application_*.sh trovato"
    exit 1
fi

echo "Numero di script Application da eseguire: $scripts_count"
echo ""

# Codice di ritorno complessivo
OVERALL_RC=0

# Esegue ogni script Application_*.sh
script_num=0
for sh_file in Application_*.sh; do
    if [ ! -f "$sh_file" ]; then
        continue
    fi
   
    script_num=$((script_num + 1))
   
    script_name=$(basename "$sh_file")
    xml_name="${script_name%.sh}.xml"
    log_name="${script_name%.sh}.log"
   
    echo "##############################"
    echo "Script $script_num di $scripts_count"
    echo "##############################"
    echo "Script: $script_name"
    echo "File XML: $xml_name"
    echo "File LOG: $log_name"
    echo ""
   
    # Verifica che il file XML corrispondente esista
    if [ ! -f "$xml_name" ]; then
        echo "ATTENZIONE: File XML $xml_name non trovato per $sh_file"
        echo "Salto l'esecuzione di questo script"
        echo ""
        continue
    fi
   
    # Crea il file di log vuoto se non esiste in DEPLOY_DIR
    touch "$DEPLOY_DIR/$log_name"
    chmod 644 "$DEPLOY_DIR/$log_name"
    chown $INFA_USER:$INFA_GROUP "$DEPLOY_DIR/$log_name"
   
    # Avvia tail in background per monitorare il log
    echo "Avvio monitoraggio log..."
    tail -n 0 -F "$DEPLOY_DIR/$log_name" &
    TAIL_PID=$!
    TAIL_PIDS+=($TAIL_PID)
    echo "Tail avviata con PID: $TAIL_PID"
    echo ""
   
    # Esegui lo script Application come utente infa nella directory IDD
    echo "Esecuzione script in corso..."
    su - $INFA_USER -c "cd $DEPLOY_DIR ; ./$script_name"
    SCRIPT_RC=$?
   
    # Aggiorna il codice di ritorno complessivo
    OVERALL_RC=$((OVERALL_RC + SCRIPT_RC))
   
    echo ""
    echo "Return code: $SCRIPT_RC"
   
    if [ $SCRIPT_RC -eq 0 ]; then
        echo "✓ ESECUZIONE COMPLETATA CON SUCCESSO per: $script_name"
    else
        echo "✗ ERRORE ESECUZIONE per: $script_name (RC: $SCRIPT_RC)"
    fi
    echo ""
   
    # Piccola pausa per permettere al log di essere scritto
    sleep 2
   
    # Termina la tail specifica di questo script
    if ps -p $TAIL_PID > /dev/null 2>&1; then
        kill $TAIL_PID 2>/dev/null
    fi
   
    echo "=============================="
    echo ""
done

# FASE 5: CLEANUP E RISULTATI FINALI
echo ""
echo "=== FASE 5: Cleanup e risultati finali ==="

# Termina eventuali tail rimaste
cleanup_tail_processes

echo ""
echo "=== RIEPILOGO FINALE ==="
echo "Directory di lavoro (questo rilascio): $etl_path_abs"
echo "Directory condivisa: $DEPLOY_DIR"
echo ""

# Mostra i file di log generati per questo rilascio
echo "File di log generati da questo rilascio:"
cd "$etl_path_abs" || exit 1
for sh_file in Application_*.sh; do
    if [ -f "$sh_file" ]; then
        log_name="${sh_file%.sh}.log"
        if [ -f "$DEPLOY_DIR/$log_name" ]; then
            log_size=$(stat -c%s "$DEPLOY_DIR/$log_name" 2>/dev/null || stat -f%z "$DEPLOY_DIR/$log_name" 2>/dev/null)
            echo "  - $log_name (${log_size} bytes)"
        fi
    fi
done

echo ""
echo "Codice di ritorno complessivo: $OVERALL_RC"
echo ""

if [ $OVERALL_RC -eq 0 ]; then
    echo "✓ DEPLOY COMPLETATO CON SUCCESSO"
    echo "  Tutti gli script Application sono stati eseguiti senza errori"
else
    echo "✗ DEPLOY COMPLETATO CON ERRORI"
    echo "  Uno o più script hanno restituito errori"
    echo "  Verificare i file di log in: $DEPLOY_DIR"
fi

echo ""
echo "=========================================="
echo "FINE ESECUZIONE"
echo "=========================================="
echo ""

exit $OVERALL_RC
