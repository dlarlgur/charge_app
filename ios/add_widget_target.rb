# -*- coding: utf-8 -*-
# ChargeWidget WidgetKit extension 타겟을 Runner.xcodeproj 에 추가한다(멱등).
# CocoaPods 번들 xcodeproj gem 으로 실행:
#   RUBYLIB=<gem lib paths> ruby ios/add_widget_target.rb
require 'xcodeproj'

PROJECT = File.expand_path('Runner.xcodeproj', __dir__)
TARGET_NAME = 'ChargeWidget'
BUNDLE_ID = 'com.dksw.chargeHelper.ChargeWidget'
TEAM = 'Z4BC92P83W'
GROUP_DIR = 'ChargeWidget'

proj = Xcodeproj::Project.open(PROJECT)
runner = proj.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found' unless runner

# --- 기존(깨진) 타겟/참조 정리 → 멱등 재생성 ---
old = proj.targets.find { |t| t.name == TARGET_NAME }
if old
  # Runner 의 embed/deps 에서 제거
  runner.dependencies.dup.each do |d|
    d.remove_from_project if d.target == old
  end
  runner.build_phases.each do |ph|
    next unless ph.respond_to?(:files)
    ph.files.dup.each do |bf|
      nm = (bf.file_ref&.path || bf.display_name).to_s
      bf.remove_from_project if nm.include?('ChargeWidget.appex') || bf.file_ref.nil?
    end
  end
  old.product_reference&.remove_from_project
  old.remove_from_project
  puts "[clean] removed previous '#{TARGET_NAME}' target"
end

deploy = runner.build_configurations.first.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '14.0'

# --- 정식 API 로 app_extension 타겟 생성 (product_reference 자동 생성) ---
ext = proj.new_target(:app_extension, TARGET_NAME, :ios, deploy, proj.products_group, :swift)

# 소스 그룹 + 파일
group = proj.main_group.find_subpath(GROUP_DIR, true)
group.set_source_tree('SOURCE_ROOT')
swift_ref = group.files.find { |f| f.path&.end_with?('ChargeWidget.swift') } ||
            group.new_reference(File.join(GROUP_DIR, 'ChargeWidget.swift'))
group.new_reference(File.join(GROUP_DIR, 'Info.plist')) unless group.files.any? { |f| f.path&.end_with?('ChargeWidget/Info.plist') }
group.new_reference(File.join(GROUP_DIR, 'ChargeWidget.entitlements')) unless group.files.any? { |f| f.path&.end_with?('.entitlements') }
ext.source_build_phase.add_file_reference(swift_ref)

# 빌드 설정
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
end

# Runner 가 extension 임베드 (Embed Foundation Extensions, dst=13 plug_ins)
embed = runner.build_phases.find { |ph|
  ph.respond_to?(:symbol_dst_subfolder_spec) && ph.symbol_dst_subfolder_spec == :plug_ins
}
unless embed
  embed = proj.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed.name = 'Embed Foundation Extensions'
  embed.symbol_dst_subfolder_spec = :plug_ins
  runner.build_phases << embed
end
bf = embed.add_file_reference(ext.product_reference)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

runner.add_dependency(ext)

proj.save
puts "[ok] '#{TARGET_NAME}' 재생성 완료"
puts "     product_reference: #{ext.product_reference.path}"
puts "     embed file_ref:   #{bf.file_ref&.path}"
