class Gcc48 < Formula
  def arch
    if Hardware::CPU.type == :intel
      if MacOS.prefer_64_bit?
        'x86_64'
      else
        'i686'
      end
    elsif Hardware::CPU.type == :ppc
      if MacOS.prefer_64_bit?
        'powerpc64'
      else
        'powerpc'
      end
    end
  end

  def osmajor
    `uname -r`.chomp
  end

  homepage 'https://gcc.gnu.org'
  url 'http://ftpmirror.gnu.org/gcc/gcc-4.8.4/gcc-4.8.4.tar.bz2'
  mirror 'ftp://gcc.gnu.org/pub/gcc/releases/gcc-4.8.4/gcc-4.8.4.tar.bz2'
  sha1 '40867a9ac74a054b1cee855988fd680cabf42006'

  head 'svn://gcc.gnu.org/svn/gcc/branches/gcc-4_8-branch'

  bottle do
    root_url "https://downloads.sf.net/project/machomebrew/Bottles/versions"
    sha1 "ae01f3b6be5b2b2734cc83d889ec96acbae9861c" => :yosemite
    sha1 "941c2b6a78ec6eeb3f86d75a25a41d14673b5102" => :mavericks
    sha1 "96c8003356a98c2a77961749eee3d33eb77711bc" => :mountain_lion
  end

  option 'enable-fortran', 'Build the gfortran compiler'
  option 'enable-java', 'Build the gcj compiler'
  option 'enable-all-languages', 'Enable all compilers and languages, except Ada'
  option 'enable-nls', 'Build with native language support (localization)'
  option 'enable-profiled-build', 'Make use of profile guided optimization when bootstrapping GCC'
  # enabling multilib on a host that can't run 64-bit results in build failures
  if OS.mac?
    option "without-multilib", "Build without multilib support" if MacOS.prefer_64_bit?
  else
    option "with-multilib", "Build with multilib support"
  end

  depends_on "binutils" if build.with? "glibc"
  depends_on "glibc" => :optional
  depends_on 'gmp'
  depends_on 'libmpc'
  depends_on 'mpfr'
  depends_on 'cloog'
  depends_on 'isl'
  depends_on 'ecj' if build.include? 'enable-java' or build.include? 'enable-all-languages'

  # The as that comes with Tiger isn't capable of dealing with the
  # PPC asm that comes in libitm
  depends_on 'cctools' => :build if OS.mac? && MacOS.version < :leopard

  fails_with :gcc_4_0
  fails_with :llvm

  # GCC bootstraps itself, so it is OK to have an incompatible C++ stdlib
  cxxstdlib_check :skip

  def version_suffix
    version.to_s.slice(/\d\.\d/)
  end

  def install
    # GCC will suffer build errors if forced to use a particular linker.
    ENV.delete 'LD'

    if OS.mac? && MacOS.version < :leopard
      ENV["AS"] = ENV["AS_FOR_TARGET"] = "#{Formula["cctools"].bin}/as"
    end

    if build.include? 'enable-all-languages'
      # Everything but Ada, which requires a pre-existing GCC Ada compiler
      # (gnat) to bootstrap. GCC 4.6.0 add go as a language option, but it is
      # currently only compilable on Linux.
      languages = %w[c c++ fortran java objc obj-c++]
    else
      # C, C++, ObjC compilers are always built
      languages = %w[c c++ objc obj-c++]

      languages << 'fortran' if build.include? 'enable-fortran'
      languages << 'java' if build.include? 'enable-java'
    end

    args = [
      ("--build=#{arch}-apple-darwin#{osmajor}" if OS.mac?),
      "--prefix=#{prefix}",
      ("--libdir=#{lib}/gcc/#{version_suffix}" if OS.mac?),
      "--enable-languages=#{languages.join(',')}",
      # Make most executables versioned to avoid conflicts.
      "--program-suffix=-#{version_suffix}",
      "--with-gmp=#{Formula["gmp"].opt_prefix}",
      "--with-mpfr=#{Formula["mpfr"].opt_prefix}",
      "--with-mpc=#{Formula["libmpc"].opt_prefix}",
      "--with-cloog=#{Formula["cloog"].opt_prefix}",
      "--with-isl=#{Formula["isl"].opt_prefix}",
      "--with-system-zlib",
      "--enable-libstdcxx-time=yes",
      "--enable-stage1-checking",
      "--enable-checking=release",
      "--enable-lto",
      # A no-op unless --HEAD is built because in head warnings will
      # raise errors. But still a good idea to include.
      "--disable-werror",
      "--with-pkgversion=Homebrew #{name} #{pkg_version} #{build.used_options*" "}".strip,
      "--with-bugurl=https://github.com/Homebrew/homebrew-versions/issues",
    ]
    if build.with? "glibc"
      binutils = Formula["binutils"].prefix/"x86_64-unknown-linux-gnu/bin"
      args += [
        "--with-native-system-header-dir=#{HOMEBREW_PREFIX}/include",
        "--with-build-time-tools=#{binutils}",
        "--with-boot-ldflags=-static-libstdc++ -static-libgcc #{ENV["LDFLAGS"]}",
      ]
    end

    # "Building GCC with plugin support requires a host that supports
    # -fPIC, -shared, -ldl and -rdynamic."
    args << "--enable-plugin" if !OS.mac? || MacOS.version > :tiger

    # Otherwise make fails during comparison at stage 3
    # See: http://gcc.gnu.org/bugzilla/show_bug.cgi?id=45248
    args << '--with-dwarf2' if OS.mac? || MacOS.version < :leopard

    args << '--disable-nls' unless build.include? 'enable-nls'

    if build.include? 'enable-java' or build.include? 'enable-all-languages'
      args << "--with-ecj-jar=#{Formula["ecj"].opt_prefix}/share/java/ecj.jar"
    end

    if build.without?("multilib") || !MacOS.prefer_64_bit?
      args << "--disable-multilib"
    else
      args << "--enable-multilib"
    end

    # Ensure correct install names when linking against libgcc_s;
    # see discussion in https://github.com/Homebrew/homebrew/pull/34303
    inreplace "libgcc/config/t-slibgcc-darwin", "@shlib_slibdir@", "#{HOMEBREW_PREFIX}/lib/gcc/#{version_suffix}"

    mkdir 'build' do
      if OS.mac? && !MacOS::CLT.installed?
        # For Xcode-only systems, we need to tell the sysroot path.
        # 'native-system-header's will be appended
        args << "--with-native-system-header-dir=/usr/include"
        args << "--with-sysroot=#{MacOS.sdk_path}"
      end

      system '../configure', *args

      if build.include? 'enable-profiled-build'
        # Takes longer to build, may bug out. Provided for those who want to
        # optimise all the way to 11.
        system 'make profiledbootstrap'
      else
        system 'make bootstrap'
      end

      # At this point `make check` could be invoked to run the testsuite. The
      # deja-gnu and autogen formulae must be installed in order to do this.

      system 'make install'
    end

    # Handle conflicts between GCC formulae

    # Since GCC 4.8 libffi stuff are no longer shipped.

    # Rename libiberty.a.
    Dir.glob(prefix/"**/libiberty.*") { |file| add_suffix file, version_suffix }

    # Rename man7.
    Dir.glob(man7/"*.7") { |file| add_suffix file, version_suffix }

    # Even when suffixes are appended, the info pages conflict when
    # install-info is run. TODO fix this.
    info.rmtree

    # Rename java properties
    if build.include? 'enable-java' or build.include? 'enable-all-languages'
      config_files = [
        "#{lib}/logging.properties",
        "#{lib}/security/classpath.security",
        "#{lib}/i386/logging.properties",
        "#{lib}/i386/security/classpath.security"
      ]

      config_files.each do |file|
        add_suffix file, version_suffix if File.exist? file
      end
    end
  end

  def post_install
    if OS.linux?
      # Create the GCC specs file
      # See https://gcc.gnu.org/onlinedocs/gcc/Spec-Files.html

      # Locate the specs file
      gcc = "gcc-#{version_suffix}"
      specs = Pathname.new(`#{bin}/#{gcc} -print-libgcc-file-name`).dirname/"specs"
      ohai "Creating the GCC specs file: #{specs}"
      raise "command failed: #{gcc} -print-libgcc-file-name" if $?.exitstatus != 0
      specs_orig = Pathname.new("#{specs}.orig")
      rm_f [specs_orig, specs]

      # Save a backup of the default specs file
      s = `#{bin}/#{gcc} -dumpspecs`
      raise "command failed: #{gcc} -dumpspecs" if $?.exitstatus != 0
      specs_orig.write s

      # Set the library search path
      if build.with?("glibc")
        s += "*link_libgcc:\n-nostdlib -L#{lib}/gcc/x86_64-unknown-linux-gnu/#{version} -L#{HOMEBREW_PREFIX}/lib\n\n"
      else
        s += "*link_libgcc:\n+ -L#{HOMEBREW_PREFIX}/lib\n\n"
      end
      s += "*link:\n+ -rpath #{HOMEBREW_PREFIX}/lib"

      # Set the dynamic linker
      glibc = Formula["glibc"]
      if glibc.installed?
        s += " --dynamic-linker #{glibc.opt_lib}/ld-linux-x86-64.so.2"
      end
      s += "\n\n"
      specs.write s
    end
  end

  def add_suffix file, suffix
    dir = File.dirname(file)
    ext = File.extname(file)
    base = File.basename(file, ext)
    File.rename file, "#{dir}/#{base}-#{suffix}#{ext}"
  end
end
