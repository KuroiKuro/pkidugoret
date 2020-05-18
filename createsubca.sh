#! /bin/sh

createsubca() {
  TEMP=`getopt -o i:c:s:t:e:k:d:p:h --long issuer:,ca:,subject:,keytype:,ecurve:,keysize:,days:,profile:,help -n 'createsubca.sh' -- "$@"`
  KEYSIZE=2048
  KEYTYPE=rsa
  ECURVE=prime256v1
  DAYS=3650
  PROFILE=v3_subca

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
      -p|--profile) PROFILE=$2; shift 2;;
      -h|--help) echo "Options:"
                 echo "  -i|--issuer <issuerca>"
		 echo "  -c|--ca <ca>"
		 echo "  -s|--subject <subject>"
		 echo " (-t|--keytype <algo>)     # default rsa (dsa,ec)"
		 echo " (-e|--ecurve <curvename>) # default prime256v1"
		 echo " (-k|--key <keysize>)      # default 2048"
		 echo " (-d|--days <days>)        # default 3650"
		 echo " (-p|--profile <profile>)  # default v3_subca"
		 shift
		 exit 1
		 ;;
      --) shift; break;;
      *) echo "internal error"; exit 1;;
    esac
  done

  if [ -z "$ISSUERCA" ]; then
    echo "Issuing CA identifier is missing."
    exit 1
  fi

  if [ -z "$CA" ]; then
    echo "CA identifier is missing."
    exit 1
  fi

  if [ -z "$SUBJECTDN" ]; then
    echo "CA subject name is missing."
    exit 1
  fi

  case $KEYTYPE in
    rsa|dsa|ec) ;;
    *) echo "Wrong key type"; exit 1;;
  esac
  
  # Create Openssl conf specific file
  cp conf/SUBJUNKCA.cnf conf/SUBJUNKCA.cnf.sed
  sed -i conf/SUBJUNKCA.cnf.sed -e 's/JUNKCA/'$CA'/g' -e 's/JUNKCOUNTRY/'$COUNTRYCA'/g' -e 's/JUNKCN/'$CNCA'/g'
  mv conf/SUBJUNKCA.cnf.sed conf/$CA.cnf

  echo "====="
  echo "Creating subordinate CA $CA, named $SUBJECTDN, issued by CA $ISSUERCA"
  echo "Creating directory structure" && mkdir database/$CA database/$CA/private database/$CA/certs database/$CA/newcerts database/$CA/crl && touch database/$CA/index.txt && echo "01" > database/$CA/crlnumber && echo 1 > database/$CA/counter
  echo "Generating CA private key"
  case $KEYTYPE in
    rsa) openssl genrsa -out database/$CA/private/cakey.pem $KEYSIZE
         ;;
    dsa) openssl dsaparam -genkey -out database/$CA/private/cakey.pem $KEYSIZE
         ;;
    ec) openssl ecparam -genkey -name $ECURVE -out database/$CA/private/cakey.pem
        ;;
  esac
  echo "Generating certificate request" && openssl req -utf8 -new -config conf/$CA.cnf -key database/$CA/private/cakey.pem -batch -out database/$CA/careq.pem -subj "$SUBJECTDN"
  echo "Generating CA secret key" && dd if=/dev/urandom of=database/$CA/private/secretkey bs=1 count=16
  SECRETKEY=`od -t x1 -A n database/$ISSUERCA/private/secretkey | sed 's/ //g' | tr 'a-f' 'A-F'`
  COUNTER=`cat database/$ISSUERCA/counter`
  echo `expr $COUNTER + 1` > database/$ISSUERCA/counter
  IV=`hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/urandom`
  SERIAL=`echo -n $COUNTER | openssl enc -e -K $SECRETKEY -iv $IV -aes-128-cbc | od -t x1 -A n | sed 's/ //g' | tr 'a-f' 'A-F'`
  echo $SERIAL > database/$ISSUERCA/serial
  echo "Creating CA certificate" && openssl ca -utf8 -config conf/$ISSUERCA.cnf -in database/$CA/careq.pem -days $DAYS -out database/$CA/cacert.pem -extensions $PROFILE -batch
  echo "Updating store" && cp database/$CA/cacert.pem store/$ISSUERCA-$CA.pem && cd store && ./hashit.sh $ISSUERCA-$CA.pem
  echo "====="
}

createsubca "$@"
