#! /bin/sh

renewrootca() {
  TEMP=`getopt -o c:t:e:k:d:h --long ca:,keytype:,ecurve:,keysize:,days:,help -n 'renewrootca.sh' -- "$@"`
  KEYSIZE=2048
  KEYTYPE=rsa
  ECURVE=prime256v1
  DAYS=3650

  eval set -- "$TEMP"
  while true; do
    case "$1" in
      -c|--ca) CA=$2; shift 2;;
      -t|--keytype) KEYTYPE=$2; shift 2;;
      -e|--ecurve) ECURVE=$2; shift 2;;
      -k|--keysize) KEYSIZE=$2; shift 2;;
      -d|--days) DAYS=$2; shift 2;;
      -h|--help) echo "Options:"
		 echo "  -c|--ca <ca>"
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

  if [ -z "$CA" ]; then
    echo "CA identifier is missing."
    exit 1
  fi

  case $KEYTYPE in
    rsa|dsa|ec) ;;
    *) echo "Wrong key type."; exit 1;;
  esac

  echo "====="
  echo "Getting current CA subject name" && SUBJECTDN=`openssl x509 -in database/$CA/cacert.pem -subject -noout | sed 's/subject= //'`
  # TODO: CA is not always UTF8, look for a solution
  echo "Renewing root CA $CA, named $SUBJECTDN"
  echo "Generating CA private key"
  case $KEYTYPE in
    rsa) openssl genrsa -out database/$CA/private/cakey.pem $KEYSIZE
         ;;
    dsa) openssl dsaparam -genkey -out database/$CA/private/cakey.pem $KEYSIZE
         ;;
    ec) openssl ecparam -genkey -name $ECURVE -out database/$CA/private/cakey.pem
        ;;
  esac
  SECRETKEY=`od -t x1 -A n database/$CA/private/secretkey | sed 's/ //g' | tr 'a-f' 'A-F'`
  COUNTER=`cat database/$CA/counter`
  echo `expr $COUNTER + 1` > database/$CA/counter
  SERIALHEX=`echo -n $COUNTER | openssl enc -e -K $SECRETKEY -iv 00000000000000000000000000000000 -aes-128-cbc | od -t x1 -A n | sed 's/ //g' | tr 'a-f' 'A-F'`
  SERIAL=`(echo ibase=16; echo $SERIALHEX) | bc -l`
  echo "Creating self-signed certificate" && openssl req -utf8 -config conf/$CA.cnf -key database/$CA/private/cakey.pem -extensions v3_ca -x509 -new -out database/$CA/cacert.pem -days $DAYS -batch -subj "$SUBJECTDN" -set_serial $SERIAL
  echo "Updating store" && cp database/$CA/cacert.pem store/$CA.pem && cd store && ./hashit.sh $CA.pem
  echo "====="
}

renewrootca "$@"
