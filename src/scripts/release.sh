#!/bin/bash

# exit on error
set -e

NAME=BadApplePi_$(date +"%Y%m%d_%H%M")_$USER

DIR=releases/${NAME}
mkdir -p ${DIR}

for MODEL in rpi
do    
    # compile normal kernel
    ./clobber.sh
    ./configure_${MODEL}.sh -DDEBUG=1
    make -B -j
    mv kernel*.img ${DIR}
done

cp -a firmware/* ${DIR}

# Create a simple README.txt file
cat >${DIR}/README.txt <<EOF
Bad Apple Pi

(c) 2018 Chris Morley (cmorley) and David Banks (hoglet)

  git version: $(grep GITVERSION gitversion.h  | cut -d\" -f2)
build version: ${NAME}
EOF

cp config.txt cmdline.txt ${DIR}
cd releases/${NAME}
zip -qr ../${NAME}.zip .
cd ../..

unzip -l releases/${NAME}.zip
 
