# -*- coding: utf-8 -*-
# ChargeWidget WidgetKit extension 타겟을 Runner.xcodeproj 에 추가한다.
# CocoaPods 번들 xcodeproj gem 으로 실행:
#   RUBYLIB=<gem lib paths> ruby ios/add_widget_target.rb
require 'xcodeproj'

PROJECT = File.expand_path('Runner.xcodeproj', __dir__)
TARGET_NAME = 'ChargeWidget'
BUNDLE_ID = 'com.dksw.chargeHelper.ChargeWidget'
TEAM = 'Z4BC92P83W'
GROUP_DIR = 'ChargeWidget'

proj = Xcodeproj::Project.open(PROJECT)

# 이미 있으면 재생성 방지
if proj.targets.any? { |t| t.name == TARGET_NAME }
  puts "[skip] target '#{TARGET_NAME}' already exists"
  exit 0
end

runner = proj.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found' unless runner

# 배포 타겟(앱과 동일: 14.0). MARKETING_VERSION / CURRENT_PROJECT_VERSION 은 Runner 값 상속.
deploy = runner.build_configurations.first.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '14.0'

# 1) app extension 타겟 생성
ext = proj.new(Xcodeproj::Project::Object::PBXNativeTarget)
proj.targets << ext
ext.name = TARGET_NAME
ext.product_name = TARGET_NAME
ext.product_type = 'com.apple.product-type.app-extension'
ext.build_configuration_list = Xcodeproj::Project::ProjectHelper.configuration_list(
  proj, :ios, deploy, :application, nil
)

# 2) 소스/리소스 그룹 + 파일 참조
group = proj.main_group.find_subpath(GROUP_DIR, true)
group.set_source_tree('SOURCE_ROOT')
swift_ref = group.new_reference(File.join(GROUP_DIR, 'ChargeWidget.swift'))
plist_ref = group.new_reference(File.join(GROUP_DIR, 'Info.plist'))
ent_ref   = group.new_reference(File.join(GROUP_DIR, 'ChargeWidget.entitlements'))

# 3) 빌드 페이즈
src_phase = ext.new_shell_script_build_phase('Sources placeholder') # placeholder 제거 후 진짜 생성
ext.build_phases.delete(src_phase)
compile = proj.new(Xcodeproj::Project::Object::PBXSourcesBuildPhase)
ext.build_phases << compile
compile.add_file_reference(swift_ref)
frameworks = proj.new(Xcodeproj::Project::Object::PBXFrameworksBuildPhase)
ext.build_phases << frameworks
resources = proj.new(Xcodeproj::Project::Object::PBXResourcesBuildPhase)
ext.build_phases << resources

# 4) 빌드 설정 (모든 configuration)
ext.build_configurations.each do |cfg|
  bs = cfg.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bs['INFOPLIST_FILE'] = "#{GROUP_DIR}/Info.plist"
  bs['CODE_SIGN_ENTITLEMENTS'] = "#{GROUP_DIR}/ChargeWidget.entitlements"
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = deploy
  bs['DEVELOPMENT_TEAM'] = TEAM
  bs['CODE_SIGN_STYLE'] = 'Automatic'
  bs['SWIFT_VERSION'] = '5.0'
  bs['TARGETED_DEVICE_FAMILY'] = '1,2'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['SKIP_INSTALL'] = 'YES'
  bs['MARKETING_VERSION'] = '$(MARKETING_VERSION)'
  bs['CURRENT_PROJECT_VERSION'] = '$(CURRENT_PROJECT_VERSION)'
  bs['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  bs['ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME'] = 'WidgetBackground'
end

# 5) Runner 에 extension 임베드 (Embed App Extensions)
embed = runner.build_phases.find { |ph|
  ph.respond_to?(:symbol_dst_subfolder_spec) && ph.symbol_dst_subfolder_spec == :plug_ins
}
unless embed
  embed = proj.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed.name = 'Embed Foundation Extensions'
  embed.symbol_dst_subfolder_spec = :plug_ins
  runner.build_phases << embed
end
appex = embed.add_file_reference(ext.product_reference)
appex.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# 6) Runner 가 extension 을 의존(먼저 빌드)
runner.add_dependency(ext)

proj.save
puts "[ok] '#{TARGET_NAME}' target added → #{PROJECT}"
puts "     bundle id: #{BUNDLE_ID}"
