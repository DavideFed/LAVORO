#!/bin/bash

# Configurazione
RC_FILE="rc_file.tmp"
ERROR_LOG_FILE="error_logs.tmp"
PMREP_IMPORT_FILE="pmrep_import"
INFA_USER="infa"
INFA_GROUP="infa"

# Configurazione cartella condivisa
SHARED_BASE_DIR="/GFS/infa/infa_shared"
DEPLOY_DIR="$SHARED_BASE_DIR/IBM_DevOps_Deploy"
ERROR_DIR="$DEPLOY_DIR/ERRORI"

# Definizione della directory di lavoro ETL
dir2="${p:set-folders/environmentEtlFolder}"
etl_path="$dir2"

# Funzione per aggiornare i codici di ritorno
update_return_codes() {
    local return_code=$1
    
    # Controlla se il file esiste
    if [ ! -f $RC_FILE ]; then
        touch $RC_FILE
    fi
    
    # Controlla se il file è vuoto
    if [ ! -s $RC_FILE ]; then
        echo 0 > $RC_FILE
    fi
    
    # Legge il numero dal file
    typeset -i RC_NUM=$(cat $RC_FILE)
    
    # Somma il RC_NUM corrente e il parametro passato
    RC_NUM=$(($RC_NUM + $return_code))
    echo "new RC $RC_NUM"
    
    # Salva nel file
    echo $RC_NUM > $RC_FILE
}

# Funzione per creare le directory condivise
create_shared_directories() {
    echo "=== Creazione directory condivise ==="
    
    # Crea la directory base se non esiste
    if [ ! -d "$SHARED_BASE_DIR" ]; then
        echo "Creazione directory base: $SHARED_BASE_DIR"
        mkdir -p "$SHARED_BASE_DIR"
    fi
    
    # Crea la directory IBM_DevOps_Deploy
    if [ ! -d "$DEPLOY_DIR" ]; then
        echo "Creazione directory deploy: $DEPLOY_DIR"
        mkdir -p "$DEPLOY_DIR"
    fi
    
    # Crea la directory ERRORI
    if [ ! -d "$ERROR_DIR" ]; then
        echo "Creazione directory errori: $ERROR_DIR"
        mkdir -p "$ERROR_DIR"
    fi
    
    # Imposta i permessi per l'accesso condiviso
    echo "Impostazione permessi per accesso condiviso..."
    chmod -R 755 "$DEPLOY_DIR"
    chown -R $INFA_USER:$INFA_GROUP "$DEPLOY_DIR"
    
    echo "Directory condivise create e configurate correttamente"
}

# Funzione per copiare i file nella directory condivisa
copy_files_to_shared() {
    echo "=== Copia file nella directory condivisa ==="
    
    # Naviga nella directory ETL
    cd "$etl_path" || exit 1
    
    # Conta i file copiati
    files_copied=0
    
    # Copia solo i file .xml e .dtd nella directory condivisa
    # I file .log vengono generati durante l'esecuzione e non esistono ancora
    for file in *.xml *.dtd; do
        # Verifica che il file esista (evita il caso in cui non ci siano file del tipo specificato)
        if [ -f "$file" ]; then
            echo "Copiando: $file -> $DEPLOY_DIR/"
            cp "$file" "$DEPLOY_DIR/"
            files_copied=$((files_copied + 1))
        fi
    done
    
    # Torna alla directory di lavoro originale
    cd - > /dev/null
    
    echo "Copiati $files_copied file nella directory condivisa"
    echo "NOTA: I file .log verranno generati durante l'esecuzione e gestiti successivamente"
}

# Funzione per spostare i file in errore nella cartella ERRORI
move_error_files() {
    echo "=== Spostamento file in errore ==="
    
    if [ ! -f $ERROR_LOG_FILE ] || [ ! -s $ERROR_LOG_FILE ]; then
        echo "Nessun file in errore da spostare"
        return
    fi
    
    files_moved=0
    
    # Legge ogni file di log in errore
    while IFS= read -r error_log_file; do
        # Estrae il nome base dal file di log (DTD_nomefile.log -> nomefile)
        if [[ $error_log_file =~ DTD_(.*)\.log ]]; then
            base_name="${BASH_REMATCH[1]}"
            
            # Definisce i nomi dei file correlati
            xml_file="${base_name}.xml"
            dtd_file="DTD_${base_name}.dtd"
            log_file="DTD_${base_name}.log"
            
            echo "Spostando file in errore per: $base_name"
            
            # Sposta XML e DTD dalla directory condivisa (se presenti)
            for file in "$xml_file" "$dtd_file"; do
                if [ -f "$DEPLOY_DIR/$file" ]; then
                    echo "  Spostando dalla dir condivisa: $file -> ERRORI/"
                    mv "$DEPLOY_DIR/$file" "$ERROR_DIR/"
                    files_moved=$((files_moved + 1))
                else
                    echo "  ATTENZIONE: File $file non trovato in $DEPLOY_DIR"
                fi
            done
            
            # Sposta il file di log dalla directory ETL (dove viene generato)
            if [ -f "$etl_path/$log_file" ]; then
                echo "  Copiando dalla dir ETL: $log_file -> ERRORI/"
                cp "$etl_path/$log_file" "$ERROR_DIR/"
                files_moved=$((files_moved + 1))
            else
                echo "  ATTENZIONE: File di log $log_file non trovato in $etl_path"
            fi
        else
            echo "ATTENZIONE: Formato file di log non riconosciuto: $error_log_file"
        fi
    done < $ERROR_LOG_FILE
    
    echo "Spostati $files_moved file nella cartella ERRORI"
}

# ========================
# FASE 0: PREPARAZIONE DIRECTORY CONDIVISE
# ========================

echo "=== FASE 0: Preparazione directory condivise ==="
create_shared_directories

# ========================
# FASE 1: GENERAZIONE FILE PMREP_IMPORT
# ========================

echo "=== FASE 1: Generazione comandi pmrep ==="

# Verifica che la directory ETL esista
if [ ! -d "$etl_path" ]; then
    echo "Errore: Directory $etl_path non trovata"
    exit 1
fi

echo "Elaborazione file nella directory: $etl_path"

# Inizializza il file pmrep_import con la connessione
cat > $PMREP_IMPORT_FILE << 'EOF'
#!/bin/bash
# File generato automaticamente per l'import dei workflow Informatica

# File per tracciare i log in errore
ERROR_LOG_FILE="error_logs.tmp"
CONNECT_RC_FILE="connect_rc.tmp"

#funzione di update rc per la connessione
update_connect_return_code() {
    local return_code=$1
    
    echo "Risultato connessione pmrep: $return_code"
    echo $return_code > $CONNECT_RC_FILE
    
    if [ $return_code -eq 0 ]; then
        echo "CONNESSIONE RIUSCITA: pmrep connesso correttamente al repository"
    else
        echo "ERRORE CONNESSIONE: Impossibile connettersi al repository pmrep (RC: $return_code)"
        echo "ATTENZIONE: I comandi successivi potrebbero fallire a causa della mancata connessione"
    fi
}

#funzione di update rc e gestione errori per gli import
update_return_codes() {
    local return_code=$1
    local log_file_name=$2
    RC_FILE=rc_file.tmp
    
    # Controlla se il file esiste
    if [ ! -f $RC_FILE ]; then
        touch $RC_FILE
    fi
    
    # Controlla se il file è vuoto
    if [ ! -s $RC_FILE ]; then
        echo 0 > $RC_FILE
    fi
    
    # Legge il numero dal file
    typeset -i RC_NUM=$(cat $RC_FILE)
    
    # Somma il RC_NUM corrente e il parametro passato
    RC_NUM=$(($RC_NUM + $return_code))
    echo "new RC $RC_NUM"
    
    # Salva nel file
    echo $RC_NUM > $RC_FILE
    
    # Se il return code è diverso da 0, salva il nome del file di log negli errori
    if [ $return_code -ne 0 ]; then
        echo "ERRORE IMPORT rilevato per il file: $log_file_name (RC: $return_code)"
        echo "$log_file_name" >> $ERROR_LOG_FILE
    else
        echo "IMPORT COMPLETATA CON SUCCESSO per il file: $log_file_name"
        echo ""
    fi
}
EOF

# Aggiunge il comando di connessione con controllo
cat >> $PMREP_IMPORT_FILE << 'EOF'

echo "=== FASE CONNESSIONE PMREP ==="
echo "Tentativo di connessione al repository..."
EOF

echo "${p:environment/pmrep_connect}" >> $PMREP_IMPORT_FILE

cat >> $PMREP_IMPORT_FILE << 'EOF'
update_connect_return_code $?

# Controlla se la connessione è riuscita prima di procedere
if [ -f $CONNECT_RC_FILE ]; then
    CONNECT_RC=$(cat $CONNECT_RC_FILE)
    if [ $CONNECT_RC -ne 0 ]; then
        echo "ERRORE FATALE: Connessione pmrep fallita. Impossibile procedere con gli import."
        exit $CONNECT_RC
    fi
fi

echo ""
echo "=== FASE IMPORT FILES ==="
EOF

# Determina il percorso relativo pulito della directory ETL
etl_clean_path=$(echo "$etl_path" | sed 's|/$||')  # Rimuove il trailing slash
pmrep_import_absolute_path=$(pwd)/$PMREP_IMPORT_FILE

# Naviga nella directory ETL specifica
cd "$etl_path" || exit 1

# Genera i comandi per ogni file XML
commands_generated=0
for xml_file in *.xml; do
    # Verifica che il file esista (evita il caso in cui non ci siano file .xml)
    if [ ! -f "$xml_file" ]; then
        echo "Nessun file XML trovato nella directory"
        break
    fi
    
    # Estrae il nome base del file (senza estensione)
    base_name=$(basename "$xml_file" .xml)
    
    # Costruisce i nomi dei file correlati
    dtd_file="DTD_${base_name}.dtd"
    log_file="DTD_${base_name}.log"
    
    # Verifica che il file DTD corrispondente esista
    if [ ! -f "$dtd_file" ]; then
        echo "Attenzione: File DTD $dtd_file non trovato per $xml_file"
        continue
    fi
    
    echo "Preparazione comando per coppia: $xml_file - $dtd_file"
    

    
    # Aggiunge i comandi al file pmrep_import (usando percorsi relativi e passando il nome del log file)
    cat >> "$pmrep_import_absolute_path" << EOF

# Crea il file di log vuoto se non esiste
echo "##############################"
echo ""
# Elaborazione di $xml_file
echo "Processando: $xml_file -> $etl_clean_path/$log_file"
touch "$etl_clean_path/$log_file"
echo "LOG DI IMPORT: $log_file"

tail -n 0 -F "$etl_clean_path/$log_file" &

# Esegui l'import
pmrep objectimport -i "$etl_clean_path/$xml_file" -c "$etl_clean_path/$dtd_file" -l "$etl_clean_path/$log_file"
update_return_codes \$? "$log_file"
echo "##############################"
echo ""
EOF
    commands_generated=$((commands_generated + 1))

done

# Torna alla directory di lavoro originale
cd - > /dev/null

if [ $commands_generated -eq 0 ]; then
    echo "Errore: Nessun comando generato. Verificare i file XML/DTD nella directory $etl_path del server o nella cartella etl sul pacchetto versionato"
    exit 1
fi

echo "Numero di comandi generati nel file $PMREP_IMPORT_FILE : $commands_generated  "

# ========================
# FASE 2: PREPARAZIONE AMBIENTE E ESECUZIONE
# ========================

echo "=== FASE 2: Preparazione ambiente ==="

# Pulisce i file di controllo nella directory corrente
> $RC_FILE
> $ERROR_LOG_FILE

# Copia i file nella directory condivisa
copy_files_to_shared

#do i permessi ad infa alla cartella dell'agente nel caso non li abbia

# Estrai ogni componente del path e verifica permessi sulle cartelle precedenti, serve per nuovi componenti. non lo fa se li ha già
#DEBUG echo "Aggiungo permessi rwx per $INFA_USER su tutte le cartelle e file a partire da $(pwd)"

# 1. Assegna permessi rx (traversal) a 'infa' su tutte le directory madri
DIR="$(pwd)"
IFS='/' read -ra PARTS <<< "$DIR"
CURRENT="/"

for part in "${PARTS[@]}"; do
    [[ -z "$part" ]] && continue
    CURRENT="$CURRENT$part"

    # Aggiungi permesso x a 'infa' solo se non già presente
    if ! getfacl -p "$CURRENT" 2>/dev/null | grep -q "^user:$INFA_USER:.*x"; then
        echo "Aggiungo permesso x per $INFA_USER su $CURRENT"
        setfacl -m "u:$INFA_USER:--x" "$CURRENT"
    fi

    CURRENT="$CURRENT/"
done

# 2. Assegna permessi rwx per 'infa' su tutte le directory sotto la directory corrente
find . -type d -exec setfacl -m "u:$INFA_USER:rwx" {} +

# 3. Assegna permessi rw per 'infa' su tutti i file sotto la directory corrente
find . -type f -exec setfacl -m "u:$INFA_USER:rw-" {} +

# 4. Imposta ACL mask a rwx così i permessi diventano effettivi (su tutti i file/cartelle coinvolti)
#    Nota: solo all'interno dell'albero corrente
find . \( -type f -o -type d \) -exec setfacl -m "m::rwx" {} +

# 5. Rende eseguibile il file script pmrep_import solo per 'infa'
setfacl -m "u:$INFA_USER:rwx" "$PMREP_IMPORT_FILE"
setfacl -m "m::rwx" "$PMREP_IMPORT_FILE"

# ========================
# FASE 3: ESECUZIONE COME UTENTE INFA
# ========================

echo "=== FASE 3: Esecuzione import ==="

# Esegue l'import come utente infa nella directory corrente
current_dir=$(pwd)

# Per il debug, mostra il contenuto del file prima dell'esecuzione
#DEBUG echo "DEBUG: Contenuto del file $PMREP_IMPORT_FILE:"
#DEBUG echo "----------------------------------------"
#DEBUG cat $PMREP_IMPORT_FILE
#DEBUG echo "----------------------------------------"


# Eseguo il file pmrep_import come utente infa

su - $INFA_USER -c "cd $current_dir ; ./$PMREP_IMPORT_FILE"

# ========================
# FASE 4: CONTROLLO RISULTATI E GESTIONE ERRORI
# ========================

echo "=== FASE 4: Controllo risultati ==="

# File per il controllo della connessione
CONNECT_RC_FILE="connect_rc.tmp"

# Controlla prima il risultato della connessione
echo "=== RISULTATO CONNESSIONE PMREP ==="
if [ -f $CONNECT_RC_FILE ]; then
    CONNECT_RC=$(cat $CONNECT_RC_FILE)
    if [ $CONNECT_RC -eq 0 ]; then
        echo "✓ CONNESSIONE PMREP: RIUSCITA"
    else
        echo "✗ CONNESSIONE PMREP: FALLITA (RC: $CONNECT_RC)"
        echo "  Tutti gli import successivi sono stati saltati"
        exit $CONNECT_RC
    fi
else
    echo "⚠ STATO CONNESSIONE: Non determinato (file di controllo mancante)"
fi

echo ""
echo "=== RISULTATO IMPORT FILES ==="

# Controlla il file ReturnCode per gli import
if [ -f $RC_FILE ]; then
    # Calcola la somma di tutti i codici di ritorno
    typeset -i RC_NUM=0
    while IFS= read -r line; do
        RC_NUM=$((RC_NUM + line))
    done < $RC_FILE
    
#DEBUG    echo "Codice di ritorno finale import: $RC_NUM"
    
    if [ $RC_NUM -eq 0 ]; then
        echo "✓ IMPORT FILES: Tutti gli import sono stati completati senza errori"
			for log_file in "$etl_path"/DTD_*.log; do
				if [ -f "$log_file" ]; then
					cp "$log_file" "$DEPLOY_DIR/"
					echo " Copiato file di log: $(basename "$log_file") dentro la share comune $DEPLOY_DIR"
			    fi
		    done
    else
        echo "✗ IMPORT FILES: Completato con errori. Codice di ritorno: $RC_NUM"
        
        # Controlla se esistono file di log in errore
        if [ -f $ERROR_LOG_FILE ] && [ -s $ERROR_LOG_FILE ]; then
            echo ""
            echo "=== REPORT DETTAGLIATO ERRORI ==="
            echo "I seguenti file hanno generato errori:"
            
            error_count=0
            while IFS= read -r error_log_file; do
                error_count=$((error_count + 1))
                echo ""
                echo "----------------------------------------"
                echo "ERRORE #$error_count - File: $error_log_file"
                echo "----------------------------------------"
                
                # Verifica se il file di log esiste nella directory ETL
                if [ -f "$etl_path/$error_log_file" ]; then
                    echo "Contenuto del file di log:"
                    echo ""
                    cat "$etl_path/$error_log_file"
                else
                    echo "ATTENZIONE: File di log $etl_path/$error_log_file non trovato!"
                fi
                echo "----------------------------------------"
            done < $ERROR_LOG_FILE
            
            echo ""
            echo "=== FINE REPORT ERRORI ==="
            echo "Totale file in errore: $error_count"
            
            # Sposta i file in errore nella cartella ERRORI
            echo ""
            move_error_files
        else
            echo "ATTENZIONE: Codice di ritorno non zero ma nessun file di errore registrato."
        fi
    fi
    
    # Termina il monitoraggio killando le tail appese
		for log_file in "$etl_path"DTD_*.log; do
			if [ -f "$log_file" ]; then
			echo "DEBUG: KILL $log_file "
			    kill $(pgrep -f "tail.*$log_file*")
            else
                echo "Nessun processo tail trovato per: $log_file"
			fi
		done    
    
    
    echo ""
    echo "=== RIEPILOGO FINALE ==="
    echo "Directory condivisa: $DEPLOY_DIR"
    if [ -f $ERROR_LOG_FILE ] && [ -s $ERROR_LOG_FILE ]; then
        echo "File in errore spostati in: $ERROR_DIR"
        echo "File processati correttamente disponibili in: $DEPLOY_DIR"
    else
        echo "Tutti i file processati correttamente sono disponibili in: $DEPLOY_DIR"
    fi
    
    exit $RC_NUM
else
    echo "ERRORE: File di return code per i comandi di import non trovato"
    exit 1
fi
