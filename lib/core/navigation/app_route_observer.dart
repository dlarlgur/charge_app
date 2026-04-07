import 'package:flutter/material.dart';

/// `/home` 등에서 다른 화면이 push된 뒤 pop될 때 `RouteAware.didPopNext`로 감지
final RouteObserver<PageRoute<void>> appRouteObserver = RouteObserver<PageRoute<void>>();
