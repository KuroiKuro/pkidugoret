#! /bin/sh

createrootca() {
  TEMP=`getopt -o c:C:n:s:t:e:k:d:h --long ca:,Country:,name:,subject:,keytype:,ecurve:,keysize:,days:,help -n 'createrootca.sh' -- "$@"`
	  KEYSIZE=2048
  KEYTYPE=rsa
  ECURVE=prime256v1
  DAYS=3650

  eval set -- "$TEMP"
  while true; do
    case "$1" in
      -c|--ca) CA=$2; shift 2;;
      -C|--Country) COUNTRYCA=$2; shift 2;;
      -n|--name) CNCA=$2; shift 2;;
      -s|--subject) SUBJECTDN="$2"; shift 2;;
      -t|--keytype) KEYTYPE=$2; shift 2;;
      -e|--ecurve) ECURVE=$2; shift 2;;
      -k|--keysize) KEYSIZE=$2; shift 2;;
      -d|--days) DAYS=$2; shift 2;;
      -h|--help) echo "Options:"
                 echo "  -c|--ca <ca>"
                 echo "  -C|--country <country>"
                 echo "  -cn|--commonname <CN>"
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
    *) echo "Wrong key type."; exit 1;;
  esac

  echo "====="
  echo "Creating root CA $CA, named $SUBJECTDN"
  echo "Creating directory structure" && mkdir -p database/$CA database/$CA/private database/$CA/certs database/$CA/newcerts database/$CA/crl && touch database/$CA/index.txt && echo "01" > database/$CA/crlnumber && echo 1 > database/$CA/counter
  echo "Generating CA private key"
  case $KEYTYPE in
    rsa) openssl genrsa -out database/$CA/private/cakey.pem $KEYSIZE
         ;;
    dsa) openssl dsaparam -genkey -out database/$CA/private/cakey.pem $KEYSIZE
         ;;
    ec) openssl ecparam -genkey -name $ECURVE -out database/$CA/private/cakey.pem
        ;;
  esac
  echo "Generating CA secret key" && dd if=/dev/urandom of=database/$CA/private/secretkey bs=1 count=16
  SECRETKEY=`od -t x1 -A n database/$CA/private/secretkey | sed 's/ //g' | tr 'a-f' 'A-F'`
  COUNTER=`cat database/$CA/counter`
  echo `expr $COUNTER + 1` > database/$CA/counter
  IV=`hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/urandom`
  SERIALHEX=`echo -n $COUNTER | openssl enc -e -K $SECRETKEY -iv $IV -aes-128-cbc | od -t x1 -A n | sed 's/ //g' | tr 'a-f' 'A-F'`
  SERIAL=`(echo ibase=16; echo $SERIALHEX) | bc -l`

  # Create Openssl conf specific file
  cp conf/JUNKCA.cnf conf/JUNKCA.cnf.sed
  sed -i conf/JUNKCA.cnf.sed -e 's/JUNKCA/'$CA'/g' -e 's/JUNKCOUNTRY/'$COUNTRYCA'/g' -e 's/JUNKCN/'$CNCA'/g'
  mv conf/JUNKCA.cnf.sed conf/$CA.cnf

  echo "Creating self-signed certificate" && openssl req -utf8 -config conf/$CA.cnf -key database/$CA/private/cakey.pem -extensions v3_ca -x509 -new -out database/$CA/cacert.pem -days $DAYS -batch -subj "$SUBJECTDN" -set_serial $SERIAL
  echo "Updating store" && cp database/$CA/cacert.pem store/$CA.pem && cd store && ./hashit.sh $CA.pem
  echo "====="
}

createrootca "$@"
