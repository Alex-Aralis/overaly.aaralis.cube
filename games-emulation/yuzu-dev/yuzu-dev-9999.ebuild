# Copyright 2020 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="A Nintendo Switch emulator"
HOMEPAGE="https://yuzu-emu.org/"
SRC_URI=""
LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~amd64 ~x86"
IUSE="system-xbyak system-opus system-qt5 early-access mainline gui desktop cli test qt-translations generic abi_x86_32 abi_x86_64 +sdl2 qt-webengine qt5 +boxcat +webservice discord +cubeb vulkan"
REQUIRED_USE="
	!qt5? ( !qt-webengine  !qt-translations !system-qt5 )
	!gui? ( !desktop !qt5 )
	|| ( gui cli test )
	^^ ( mainline early-access )
"
RESTRICT="
	!early-access? ( fetch )
	!test? ( test )
"

DEPEND=""
BDEPEND="
	early-access? ( dev-vcs/hub )
	mainline? ( dev-vcs/hub )
"
RDEPEND="
	system-qt5? (
		qt5? ( >=dev-qt/qtwidgets-5.9:5 )
		qt-translations? ( >=dev-qt/qttranslations-5.9:5 )
		qt-webengine? ( >=dev-qt/qtwebengine-5.9:5[widgets] )
	)
	system-xbyak? (
		abi_x86_64? ( !generic? ( >=dev-libs/xbyak-5.91 ) )
		abi_x86_32? ( !generic? ( >=dev-libs/xbyak-5.91 ) )
	)
	system-opus? ( >=media-libs/opus-1.3.1 )
	sdl2? ( media-libs/libsdl2 )
	>=app-arch/lz4-1.8
	>=dev-cpp/catch-2.11
	>=dev-cpp/nlohmann_json-3.7
	>=app-arch/zstd-1.4
	>=sys-libs/zlib-1.2
	>=dev-libs/libfmt-7.0
	>=dev-libs/boost-1.71[context]
	>=dev-libs/libzip-1.5
	${DEPEND}
"

PYTHON_COMPAT=( python2_7 )

inherit xdg cmake python-single-r1 git-r3

EGIT_REPO_URI="https://github.com/yuzu-emu/yuzu.git"
EGIT_SUBMODULES=( '*' )
YUZU_VARIANT=${PN##*-}

if [[ ${PV} == 9999 ]]; then
	EGIT_BRANCH="master"
else
	EGIT_COMMIT=${PV}
fi

src_unpack() {
	git-r3_src_unpack

	pushd "${S}"
	git remote add origin $EGIT_REPO_URI

	if use early-access; then
		[[ -z $GITHUB_TOKEN ]] && eerror "\$GITHUB_TOKEN must be set in make.conf to build with early-access patches."
		elog "APPLYING EARLY ACCESS PULL REQUESTS"
		hub apply --verbose $(hub pr list -L 1000 --format "%U %L%n" | grep "early-access-merge" | cut -d' ' -f1 | tr "\n" ' ')
	fi

	if use mainline || use early-access; then
		[[ -z $GITHUB_TOKEN ]] && eerror "\$GITHUB_TOKEN must be set in make.conf to build with mainline patches."
		
		elog "APPLYING MAINLINE PULL REQUESTS"
		hub apply --verbose $(hub pr list -L 1000 --format "%U %L%n" | grep "mainline-merge" | cut -d' ' -f1 | tr "\n" ' ')
	fi

	popd
}

src_prepare() {
	eapply "${FILESDIR}"/{fix-cmake,static-externals}.patch

	if [[ $YUZU_VARIANT == dev ]] && use desktop; then
		eapply "${FILESDIR}"/dev-metadata.patch
	fi

	if use system-xbyak; then
		eapply "${FILESDIR}"/unbundle-xbyak.patch
	fi

	if use system-opus; then
		eapply "${FILESDIR}"/unbundle-opus.patch
	fi

	cmake_src_prepare
	xdg_src_prepare
}

src_configure() {
	local mycmakeargs=(
		-DCMAKE_INSTALL_PREFIX="${D}/usr"
		-DUSE_DISCORD_PRESENCE=$(usex discord ON OFF)
		-DENABLE_CUBEB=$(usex cubeb ON OFF)
		-DENABLE_WEB_SERVICE=$(usex webservice ON OFF)
		-DENABLE_VULKAN=$(usex vulkan ON OFF)
		-DENABLE_SDL2=$(usex sdl2 ON OFF)
		-DYUZU_ENABLE_BOXCAT=$(usex boxcat ON OFF)
		-DYUZU_USE_BUNDLED_UNICORN=ON
		-DENABLE_QT=$(usex qt5 ON OFF)
		-DYUZU_USE_BUNDLED_QT=$(usex !system-qt5 ON OFF)
		-DYUZU_USE_QT_WEB_ENGINE=$(usex qt-webengine ON OFF)
		-DENABLE_QT_TRANSLATION=$(usex qt-translations ON OFF)
	)

	cmake_src_configure
}

src_compile() {
	cmake_src_compile $(usex gui yuzu "") $(usex cli yuzu-cmd "") $(usex test "tests yuzu-tester" "")
}

src_install() {
	debug-print-function ${FUNCNAME} "$@"

	_cmake_check_build_dir
	pushd "${BUILD_DIR}" > /dev/null || die

	local install_component="$CMAKE_BINARY --install . --component "

	# Do component installs
	use gui && $install_component yuzu
	use desktop && $install_component desktop
	use cli && $install_component yuzu-cmd
	use test && $install_component yuzu-tester

	popd > /dev/null || die

	# Rename files if varaint.
	if [[ -n $YUZU_VARIANT ]]; then
		for f in $(find "${D}" -type f); do
			local file_name=${f##*/}
			local file_path=${f%/*}
			local file_base=${file_name%.*}
			local file_ext=${file_name##*.}
			local variant_suffix=${YUZU_VARIANT:+-}${YUZU_VARIANT}

			# Special case for dot files
			if [[ $file_name =~ ^\.[^\.]*$ ]]; then
				local destination="${file_path}/${file_name}${variant_suffix}"

			# If has ext
			elif [[ $file_name =~ \. ]]; then
				local destination="${file_path}/${file_base}${variant_suffix}.${file_ext}"

			# Not dot, no extension
			else
				local destination="${file_path}/${file_name}${variant_suffix}"
			fi

			mv "$f" "$destination"
		done
	fi

	# Try to install docs
	pushd "${S}" > /dev/null || die
	einstalldocs
	popd > /dev/null || die
}
