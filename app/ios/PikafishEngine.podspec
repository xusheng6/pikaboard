Pod::Spec.new do |s|
  s.name         = 'PikafishEngine'
  s.version      = '1.0.0'
  s.summary      = 'Pikafish Xiangqi engine with bridge'
  s.homepage     = 'https://github.com/official-pikafish/Pikafish'
  s.license      = { :type => 'GPL-3.0' }
  s.author       = 'Pikafish developers'
  s.source       = { :git => '', :tag => s.version.to_s }
  s.platform     = :ios, '15.0'

  # All Pikafish source files + bridge
  s.source_files = [
    '../../Pikafish/src/**/*.{cpp,h}',
    '../../pikafish_bridge/*.{cpp,h}'
  ]

  # Exclude main.cpp and x86-only assembly
  s.exclude_files = [
    '../../Pikafish/src/main.cpp',
    '../../Pikafish/src/external/decompress/huf_decompress_amd64.S'
  ]

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'GCC_C_LANGUAGE_STANDARD' => 'c11',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../../Pikafish/src" "${PODS_TARGET_SRCROOT}/../../Pikafish/src/external" "${PODS_TARGET_SRCROOT}/../../pikafish_bridge"',
    'OTHER_CPLUSPLUSFLAGS' => '-fno-exceptions -DNDEBUG -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8 -DUSE_NEON_DOTPROD -DUSE_PTHREADS -O3 -funroll-loops',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => ''
  }

  s.libraries = 'c++'
  s.frameworks = 'Foundation'
end
