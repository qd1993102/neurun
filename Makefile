.PHONY: ios-doctor ios-open ios-build ios-test ios-archive

ios-doctor:
	bash ci/ios/check.sh doctor

ios-open:
	bash ci/ios/check.sh open

ios-build:
	bash ci/ios/check.sh build

ios-test:
	bash ci/ios/check.sh test

ios-archive:
	bash ci/ios/check.sh archive
