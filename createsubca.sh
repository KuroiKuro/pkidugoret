#! /bin/sh

createsubca() {
  TEMP=`getopt -o i:c:s:t:e:k:d:h --long issuer:,ca:,subject:,keytype:,ecurve:,keysize:,days:,help -n 'createsubca.sh' -- "$@"`
  KEYSIZE=2048
  KEYTYPE=rsa
  ECURVE=prime256v1
  DAYS=3650

  eval set -- "$TEMP"
  while true; do
    case "$1" in
      -i|--issuer) ISSUERCA=$2; shift 2;;
      -c|--ca) CA=$2; shift 2;;
      -s|--subject) SUBJECTDN="$2"; shift 2;;
      -t|--keytype) KEYTYPE=$2; shift 2;;
      -e|--ecurve) ECURVE=$2; shift 2;;
      -k|--keysize) KEYSIZE=$2; shift 2;;
      -d|--days) DAYS=$2; shift 2;;
      -h|--help) echo "Options:"
                 echo "  -i|--issuer <issuerca>"
		 echo "  -c|--ca <ca>"
		 echo "  -s|--subject <subject>"
		 echo " (-t|--keytype <algo>)     # default rsa (dsa,ec)"
		 echo " (-e|--ecurve <curvename>) # default prime256v1"
		 echo " (-k|--key <keysize>)      # default 2048"
		 echo " (-d|--days <days>)        # default 3650"
		 shift
		 exit 1
		 ;;
      --) shift; break;;
      *) echo "internal error"; exit 1;;
    esac
  done

  if [ -z "$ISSUERCA" ]; then
    echo "Il faut l'identifiant de l'AC émettrice"
    exit 1
  fi

  if [ -z "$CA" ]; then
    echo "Il faut l'identifiant de l'AC"
    exit 1
  fi

  if [ -z "$SUBJECTDN" ]; then
    echo "Il faut nommer le certificat"
    exit 1
  fi

  case $KEYTYPE in
    rsa|dsa|ec) ;;
    *) echo "Mauvais type de clé"; exit 1;;
  esac

  echo "====="
  echo "Création de l'AC fille $CA, ayant pour nom $SUBJECTDN, signée par l'AC $ISSUERCA"
  echo "Création de la structure" && mkdir database/$CA database/$CA/private database/$CA/certs database/$CA/newcerts database/$CA/crl && touch database/$CA/index.txt && echo "01" > database/$CA/crlnumber && echo 1 > database/$CA/counter
  echo "Génération de la clé privée de l'AC"
  case $KEYTYPE in
    rsa) openssl genrsa -out database/$CA/private/cakey.pem $KEYSIZE
         ;;
    dsa) openssl dsaparam -genkey -out database/$CA/private/cakey.pem $KEYSIZE
         ;;
    ec) openssl ecparam -genkey -name $ECURVE -out database/$CA/private/cakey.pem
        ;;
  esac
  echo "Génération de la requête" && openssl req -utf8 -new -config conf/$CA.cnf -key database/$CA/private/cakey.pem -batch -out database/$CA/careq.pem -subj "$SUBJECTDN"
  echo "Génération de la clé secrète" && dd if=/dev/urandom of=database/$CA/private/secretkey bs=1 count=16
  SECRETKEY=`od -t x1 -A n database/$ISSUERCA/private/secretkey | sed 's/ //g' | tr 'a-f' 'A-F'`
  COUNTER=`cat database/$ISSUERCA/counter`
  echo `expr $COUNTER + 1` > database/$ISSUERCA/counter
  SERIAL=`echo -n $COUNTER | openssl enc -e -K $SECRETKEY -iv 00000000000000000000000000000000 -aes-128-cbc | od -t x1 -A n | sed 's/ //g' | tr 'a-f' 'A-F'`
  echo $SERIAL > database/$ISSUERCA/serial
  echo "Création du certificat" && openssl ca -utf8 -config conf/$ISSUERCA.cnf -in database/$CA/careq.pem -days $DAYS -out database/$CA/cacert.pem -extensions v3_subca -batch
  echo "Mise à jour du store" && cp database/$CA/cacert.pem store/$ISSUERCA-$CA.pem && cd store && ./hashit.sh $ISSUERCA-$CA.pem
  echo "====="
}

createsubca "$@"