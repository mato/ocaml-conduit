#!/bin/sh -e

TAGS=principal,annot,bin_annot,short_paths,thread,strict_sequence
J_FLAG=2

BASE_PKG="sexplib ipaddr cstruct uri stringext"
SYNTAX_PKG="camlp4.macro sexplib.syntax"

# When cross-compiling, assume for now that shared libraries are not
# supported.
if [ -n "${OCAMLFIND_TOOLCHAIN}" ]; then
  SHARED_LIBS=
else
  SHARED_LIBS=yes
fi

# The Async backend is only supported in OCaml 4.01.0+
OCAML_VERSION=`ocamlc -version`
case $OCAML_VERSION in
4.00.*|3.*)
  echo Async backend only supported in OCaml 4.01.0 or higher
  ;;
*)
HAVE_ASYNC=`ocamlfind query async 2>/dev/null || true`
HAVE_ASYNC_SSL=`ocamlfind query async_ssl 2>/dev/null || true`
;;
esac

HAVE_LWT=`ocamlfind query lwt 2>/dev/null || true`
HAVE_LWT_SSL=`ocamlfind query lwt.ssl 2>/dev/null || true`
HAVE_LWT_TLS=`ocamlfind query tls.lwt 2>/dev/null || true`
HAVE_MIRAGE=`ocamlfind query mirage-types dns.mirage 2>/dev/null || true`
HAVE_MIRAGE_TLS=`ocamlfind query tls.mirage 2>/dev/null || true`
HAVE_VCHAN=`ocamlfind query vchan 2>/dev/null || true`
HAVE_VCHAN_LWT=`ocamlfind query vchan.lwt xen-evtchn.unix 2>/dev/null || true`

add_target () {
  TARGETS="$TARGETS lib/$1.cma lib/$1.cmxa"
  if [ -n "${SHARED_LIBS}" ]; then
    TARGETS="$TARGETS lib/$1.cmxs"
  fi
}

add_pkg () {
  PKG="$PKG $1"
}

add_pkg "$SYNTAX_PKG"
add_pkg "$BASE_PKG"
add_target "conduit"
rm -f lib/*.odocl
echo Conduit > lib/conduit.mllib
echo Conduit_trie >> lib/conduit.mllib
echo Resolver >> lib/conduit.mllib
cp lib/conduit.mllib lib/conduit.odocl

rm -f _tags
rm -rf _install
mkdir -p _install

echo 'true: syntax(camlp4o)' >> _tags

if [ "$HAVE_ASYNC" != "" ]; then
  echo "Building with Async support."
  echo "# This file is autogenerated by build.sh" > lib/conduit-async.mllib
  echo Conduit_async >> lib/conduit-async.mllib
  add_target "conduit-async"
  ASYNC_REQUIRES="async ipaddr.unix"

  if [ "$HAVE_ASYNC_SSL" != "" ]; then
    echo "Building with Async/SSL support."
    echo 'true: define(HAVE_ASYNC_SSL)' >> _tags
    ASYNC_REQUIRES="$ASYNC_REQUIRES async_ssl"
    echo Conduit_async_ssl >> lib/conduit-async.mllib
  fi
  cp lib/conduit-async.mllib lib/conduit-async.odocl
fi

if [ "$HAVE_LWT" != "" ]; then
  echo "Building with Lwt support."
  echo "# This file is autogenerated by build.sh" > lib/conduit-lwt.mllib
  echo Resolver_lwt > lib/conduit-lwt.mllib
  add_target "conduit-lwt"
  LWT_REQUIRES="lwt"
  LWT_UNIX_REQUIRES="lwt.unix ipaddr.unix uri.services"

  echo Conduit_lwt_unix > lib/conduit-lwt-unix.mllib
  echo Resolver_lwt_unix >> lib/conduit-lwt-unix.mllib
  add_target "conduit-lwt-unix"

  if [ "$HAVE_LWT_SSL" != "" ]; then
    echo "Building with Lwt/SSL support."
    echo 'true: define(HAVE_LWT_SSL)' >> _tags
    LWT_UNIX_REQUIRES="$LWT_UNIX_REQUIRES lwt.ssl"
    echo Conduit_lwt_unix_ssl >> lib/conduit-lwt-unix.mllib
  fi

  if [ "$HAVE_LWT_TLS" != "" ]; then
    echo "Building with Lwt/TLS support."
    echo 'true: define(HAVE_LWT_TLS)' >> _tags
    LWT_UNIX_REQUIRES="$LWT_UNIX_REQUIRES tls tls.lwt"
    echo Conduit_lwt_tls >> lib/conduit-lwt-unix.mllib
  fi

  cp lib/conduit-lwt.mllib lib/conduit-lwt.odocl
  cp lib/conduit-lwt-unix.mllib lib/conduit-lwt-unix.odocl

  if [ "$HAVE_MIRAGE" != "" ]; then
    echo "Building with Mirage support."
    echo 'true: define(HAVE_MIRAGE)' >> _tags
    echo Conduit_mirage > lib/conduit-lwt-mirage.mllib
    echo Resolver_mirage >> lib/conduit-lwt-mirage.mllib
    MIRAGE_REQUIRES="mirage-types dns.mirage uri.services"
    if [ "$HAVE_VCHAN" != "" ]; then
      echo "Building with Mirage Vchan support."
      echo 'true: define(HAVE_VCHAN)' >> _tags
      MIRAGE_REQUIRES="$MIRAGE_REQUIRES vchan"
      echo Conduit_xenstore >> lib/conduit-lwt-mirage.mllib
      echo '"scripts/xenstore-conduit-init" {"xenstore-conduit-init"}' > _install/bin
    fi
    if [ "$HAVE_MIRAGE_TLS" != "" ]; then
      echo "Building with Mirage TLS support."
      echo 'true: define(HAVE_MIRAGE_TLS)' >> _tags
      MIRAGE_REQUIRES="$MIRAGE_REQUIRES tls tls.mirage"
    fi
    add_target "conduit-lwt-mirage"
    cp lib/conduit-lwt-mirage.mllib lib/conduit-lwt-mirage.odocl
  fi

fi

if [ "$HAVE_VCHAN_LWT" != "" ]; then
    echo "Building with Vchan Lwt_unix support."
    echo 'true: define(HAVE_VCHAN_LWT)' >> _tags
    VCHAN_LWT_REQUIRES="vchan.lwt"
fi

# Build all the ocamldoc
if [ "$BUILD_DOC" = "true" ]; then
  cat lib/*.odocl > lib/conduit-all.odocl
  TARGETS="${TARGETS} lib/conduit-all.docdir/index.html"
fi

REQS=`echo $PKG $ASYNC_REQUIRES $LWT_REQUIRES $LWT_UNIX_REQUIRES $MIRAGE_REQUIRES $VCHAN_LWT_REQUIRES  | tr -s ' '`

# When cross-compiling, build myocamlbuild using the host compiler.
(unset OCAMLFIND_TOOLCHAIN; ocamlbuild -use-ocamlfind -just-plugin)
ocamlbuild -use-ocamlfind -classic-display -no-links -j ${J_FLAG} -tag ${TAGS} \
  -cflags "-w A-4-33-40-41-42-43-34-44" \
  -pkgs `echo $REQS | tr ' ' ','` \
  ${TARGETS}

sed \
  -e "s/@BASE_REQUIRES@/${BASE_PKG}/g" \
  -e "s/@VERSION@/`cat VERSION`/g" \
  -e "s/@ASYNC_REQUIRES@/${ASYNC_REQUIRES}/g" \
  -e "s/@LWT_REQUIRES@/${LWT_REQUIRES}/g" \
  -e "s/@LWT_UNIX_REQUIRES@/${LWT_UNIX_REQUIRES}/g" \
  -e "s/@MIRAGE_REQUIRES@/${MIRAGE_REQUIRES}/g" \
  -e "s/@VCHAN_LWT_REQUIRES@/${VCHAN_LWT_REQUIRES}/g" \
  META.in > META

if [ "$1" = "true" ]; then
  B=_build/lib/
  if [ -n "${SHARED_LIBS}" ]; then
    CMXS="$B/*.cmxs"
  else
    CMXS=
  fi
  ls $B/*.cmi $B/*.cmt $B/*.cmti $B/*.cmx $B/*.cmxa $B/*.cma $CMXS $B/*.a $B/*.o $B/*.cmo > _install/lib
  ocamlfind remove conduit || true
  FILES=`ls -1 lib/intro.html $B/*.mli $B/*.cmi $B/*.cmt $B/*.cmti $B/*.cmx $B/*.cmxa $B/*.cma $CMXS $B/*.a $B/*.o $B/*.cmo 2>/dev/null || true`
  ocamlfind install conduit META $FILES
fi
