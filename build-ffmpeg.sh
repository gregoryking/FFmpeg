#!/bin/sh
PATH=$PATH:/usr/local/bin/

echo "CONFIGURATION_TEMP_DIR: $CONFIGURATION_TEMP_DIR"
echo "CONFIGURATION_BUILD_DIR: $CONFIGURATION_BUILD_DIR"
echo "BUILD_DIR: $BUILD_DIR"
echo "CONFIGURATION: $CONFIGURATION"
echo "EFFECTIVE_PLATFORM_NAME: $EFFECTIVE_PLATFORM_NAME"


if [ "$ACTION" = "clean" ]
then
    rm -rf $CONFIGURATION_TEMP_DIR
    rm -rf $CONFIGURATION_BUILD_DIR
    exit
fi

# directories
SOURCE=""
FAT=$CONFIGURATION_BUILD_DIR

SCRATCH=$CONFIGURATION_TEMP_DIR
# must be an absolute path
THIN=$CONFIGURATION_BUILD_DIR

# absolute path to x264 library
#X264=`pwd`/fat-x264

#FDK_AAC=`pwd`/fdk-aac/fdk-aac-ios

CONFIGURE_FLAGS="--enable-cross-compile --disable-debug --disable-programs \
--disable-doc --enable-pic --enable-gpl"

if [ "$X264" ]
then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-gpl --enable-libx264"
fi

if [ "$FDK_AAC" ]
then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libfdk-aac"
fi

# avresample
#CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-avresample"

ARCHS="arm64 armv7 x86_64 i386"
#ARCHS="x86_64 i386"

COMPILE="y"
LIPO="y"

DEPLOYMENT_TARGET="6.0"

if [ "$*" ]
then
    if [ "$*" = "lipo" ]
    then
        # skip compile
        COMPILE=
    else
        ARCHS="$*"
        if [ $# -eq 1 ]
        then
            # skip lipo
            LIPO=
        fi
    fi
fi

if [ "$COMPILE" ]
then
    if [ ! `which yasm` ]
    then
        echo 'Yasm not found'
        if [ ! `which brew` ]
        then    
            echo 'Homebrew not found. Trying to install...'
            ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" \
            || exit 1
        fi
        echo 'Trying to install Yasm...'
        brew install yasm || exit 1
    fi
    if [ ! `which gas-preprocessor.pl` ]
    then
        echo 'gas-preprocessor.pl not found. Trying to install...'
        (curl -L https://github.com/libav/gas-preprocessor/raw/master/gas-preprocessor.pl \
        -o /usr/local/bin/gas-preprocessor.pl \
        && chmod +x /usr/local/bin/gas-preprocessor.pl) \
        || exit 1
    fi

    if [ ! -r $SOURCE ]
    then
        echo 'FFmpeg source not found. Trying to download...'
        curl http://www.ffmpeg.org/releases/$SOURCE.tar.bz2 | tar xj \
        || exit 1
    fi

    CWD=`pwd`
    for ARCH in $ARCHS
    do
        echo "building $ARCH..."
        mkdir -p "$SCRATCH/$ARCH"
        cd "$SCRATCH/$ARCH"

        CFLAGS="-arch $ARCH"
        if [ "$ARCH" = "i386" -o "$ARCH" = "x86_64" ]
        then
            PLATFORM="iPhoneSimulator"
            CFLAGS="$CFLAGS -mios-simulator-version-min=$DEPLOYMENT_TARGET"
        else
            PLATFORM="iPhoneOS"
            CFLAGS="$CFLAGS -mios-version-min=$DEPLOYMENT_TARGET"
            if [ "$ARCH" = "arm64" ]
            then
                EXPORT="GASPP_FIX_XCODE5=1"
            fi
        fi

        if [ ! -f "$SCRATCH/$ARCH/config_done.flag" ]
        then
            XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
            CC="xcrun -sdk $XCRUN_SDK clang"
            CXXFLAGS="$CFLAGS"
            LDFLAGS="$CFLAGS"
            if [ "$X264" ]
            then
                CFLAGS="$CFLAGS -I$X264/include"
                LDFLAGS="$LDFLAGS -L$X264/lib"
            fi
            if [ "$FDK_AAC" ]
            then
                CFLAGS="$CFLAGS -I$FDK_AAC/include"
                LDFLAGS="$LDFLAGS -L$FDK_AAC/lib"
            fi

            TMPDIR=${TMPDIR/%\/} $CWD/$SOURCE/configure \
            --target-os=darwin \
            --arch=$ARCH \
            --cc="$CC" \
            $CONFIGURE_FLAGS \
            --extra-cflags="$CFLAGS" \
            --extra-cxxflags="$CXXFLAGS" \
            --extra-ldflags="$LDFLAGS" \
            --prefix="$THIN/$ARCH" \
            || exit 1

            echo "Configuring done" > "$SCRATCH/$ARCH/config_done.flag"
        fi

        make -j3 install $EXPORT || exit 1
        cd $CWD
    done
fi

if [ "$LIPO" ]
then
    echo "building fat binaries..."
    mkdir -p $FAT/lib
    set - $ARCHS
    CWD=`pwd`
    cd $THIN/$1/lib
    for LIB in *.a
    do
        rm -f $FAT/$LIB
        cd $CWD
        echo lipo -create `find $THIN -name $LIB` -output $FAT/lib/$LIB 1>&2
        lipo -create `find $THIN -name $LIB` -output $FAT/lib/$LIB || exit 1
        mv $FAT/lib/$LIB $BUILD_DIR
    done

    cd $CWD
    cp -rf $THIN/$1/include "$BUILD_DIR/$CONFIGURATION$EFFECTIVE_PLATFORM_NAME" #looks like this needs possibly changing to $(BUILD_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME).  Also need to look into whether the clean is working and building properly.
fi

echo Done