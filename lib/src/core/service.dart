library angel_framework.http.service;

import 'dart:async';

import 'package:angel_http_exception/angel_http_exception.dart';
import 'package:merge_map/merge_map.dart';

import '../util.dart';
import 'hooked_service.dart' show HookedService;
import 'metadata.dart';
import 'request_context.dart';
import 'response_context.dart';
import 'routable.dart';
import 'server.dart';

/// Indicates how the service was accessed.
///
/// This will be passed to the `params` object in a service method.
/// When requested on the server side, this will be null.
class Providers {
  /// The transport through which the client is accessing this service.
  final String via;

  const Providers(String this.via);

  static const String viaRest = "rest";
  static const String viaWebsocket = "websocket";
  static const String viaGraphQL = "graphql";

  /// Represents a request via REST.
  static const Providers rest = Providers(viaRest);

  /// Represents a request over WebSockets.
  static const Providers websocket = Providers(viaWebsocket);

  /// Represents a request parsed from GraphQL.
  static const Providers graphql = Providers(viaGraphQL);

  @override
  bool operator ==(other) => other is Providers && other.via == via;

  @override
  String toString() {
    return 'via:$via';
  }
}

/// A front-facing interface that can present data to and operate on data on behalf of the user.
///
/// Heavily inspired by FeathersJS. <3
class Service extends Routable {
  /// A [List] of keys that services should ignore, should they see them in the query.
  static const List<String> specialQueryKeys = <String>[
    r'$limit',
    r'$sort',
    'page',
    'token'
  ];

  /// Handlers that must run to ensure this service's functionality.
  List<RequestHandler> get bootstrappers => [];

  /// The [Angel] app powering this service.
  Angel app;

  /// Closes this service, including any database connections or stream controllers.
  void close() {}

  /// Retrieves the first object from the result of calling [index] with the given [params].
  ///
  /// If the result of [index] is `null`, OR an empty [Iterable], a 404 `AngelHttpException` will be thrown.
  ///
  /// If the result is both non-null and NOT an [Iterable], it will be returned as-is.
  ///
  /// If the result is a non-empty [Iterable], [findOne] will return `it.first`, where `it` is the aforementioned [Iterable].
  ///
  /// A custom [errorMessage] may be provided.
  Future findOne(
      [Map params,
      String errorMessage = 'No record was found matching the given query.']) {
    return index(params).then((result) {
      if (result == null) {
        throw new AngelHttpException.notFound(message: errorMessage);
      } else if (result is Iterable) {
        if (result.isEmpty) {
          throw new AngelHttpException.notFound(message: errorMessage);
        } else {
          return result.first;
        }
      } else {
        return result;
      }
    });
  }

  /// Retrieves all resources.
  Future index([Map params]) {
    throw new AngelHttpException.methodNotAllowed();
  }

  /// Retrieves the desired resource.
  Future read(id, [Map params]) {
    throw new AngelHttpException.methodNotAllowed();
  }

  /// Creates a resource.
  Future create(data, [Map params]) {
    throw new AngelHttpException.methodNotAllowed();
  }

  /// Modifies a resource.
  Future modify(id, data, [Map params]) {
    throw new AngelHttpException.methodNotAllowed();
  }

  /// Overwrites a resource.
  Future update(id, data, [Map params]) {
    throw new AngelHttpException.methodNotAllowed();
  }

  /// Removes the given resource.
  Future remove(id, [Map params]) {
    throw new AngelHttpException.methodNotAllowed();
  }

  /// Transforms an [id] (whether it is a String, num, etc.) into one acceptable by a service.
  ///
  /// The single type argument, [T], is used to determine how to parse the [id].
  ///
  /// For example, `parseId<bool>` attempts to parse the value as a [bool].
  static T parseId<T>(id) {
    if (id == 'null' || id == null)
      return null;
    else if (T == String)
      return id.toString() as T;
    else if (T == int)
      return int.parse(id.toString()) as T;
    else if (T == bool)
      return (id == true || id?.toString() == 'true') as T;
    else if (T == double)
      return int.parse(id.toString()) as T;
    else if (T == num)
      return num.parse(id.toString()) as T;
    else
      return id as T;
  }

  /// Generates RESTful routes pointing to this class's methods.
  void addRoutes([Service service]) {
    _addRoutesInner(service ?? this, bootstrappers);
  }

  void _addRoutesInner(Service service, Iterable<RequestHandler> handlerss) {
    var restProvider = {'provider': Providers.rest};
    var handlers = new List<RequestHandler>.from(handlerss);

    // Add global middleware if declared on the instance itself
    Middleware before = getAnnotation(service, Middleware);

    if (before != null) handlers.addAll(before.handlers);

    Middleware indexMiddleware = getAnnotation(service.index, Middleware);
    get('/', (RequestContext req, res) {
      return req.parseQuery().then((query) {
        return this.index(mergeMap([
          {'query': query},
          restProvider,
          req.serviceParams
        ]));
      });
    },
        middleware: <RequestHandler>[]
          ..addAll(handlers)
          ..addAll((indexMiddleware == null) ? [] : indexMiddleware.handlers));

    Middleware createMiddleware = getAnnotation(service.create, Middleware);
    post('/', (RequestContext req, ResponseContext res) {
      return req.parseQuery().then((query) {
        return req.parseBody().then((body) {
          return this
              .create(
                  body,
                  mergeMap([
                    {'query': query},
                    restProvider,
                    req.serviceParams
                  ]))
              .then((r) {
            res.statusCode = 201;
            return r;
          });
        });
      });
    },
        middleware: []
          ..addAll(handlers)
          ..addAll(
              (createMiddleware == null) ? [] : createMiddleware.handlers));

    Middleware readMiddleware = getAnnotation(service.read, Middleware);

    get('/:id', (RequestContext req, res) {
      return req.parseQuery().then((query) {
        return this.read(
            parseId(req.params['id']),
            mergeMap([
              {'query': query},
              restProvider,
              req.serviceParams
            ]));
      });
    },
        middleware: []
          ..addAll(handlers)
          ..addAll((readMiddleware == null) ? [] : readMiddleware.handlers));

    Middleware modifyMiddleware = getAnnotation(service.modify, Middleware);
    patch(
        '/:id',
        (RequestContext req, res) => req.parseBody().then((body) {
              return req.parseQuery().then((query) {
                return this.modify(
                    parseId(req.params['id']),
                    body,
                    mergeMap([
                      {'query': query},
                      restProvider,
                      req.serviceParams
                    ]));
              });
            }),
        middleware: []
          ..addAll(handlers)
          ..addAll(
              (modifyMiddleware == null) ? [] : modifyMiddleware.handlers));

    Middleware updateMiddleware = getAnnotation(service.update, Middleware);
    post(
        '/:id',
        (RequestContext req, res) => req.parseBody().then((body) {
              return req.parseQuery().then((query) {
                return this.update(
                    parseId(req.params['id']),
                    body,
                    mergeMap([
                      {'query': query},
                      restProvider,
                      req.serviceParams
                    ]));
              });
            }),
        middleware: []
          ..addAll(handlers)
          ..addAll(
              (updateMiddleware == null) ? [] : updateMiddleware.handlers));
    put(
        '/:id',
        (RequestContext req, res) => req.parseBody().then((body) {
              return req.parseQuery().then((query) {
                return this.update(
                    parseId(req.params['id']),
                    body,
                    mergeMap([
                      {'query': query},
                      restProvider,
                      req.serviceParams
                    ]));
              });
            }),
        middleware: []
          ..addAll(handlers)
          ..addAll(
              (updateMiddleware == null) ? [] : updateMiddleware.handlers));

    Middleware removeMiddleware = getAnnotation(service.remove, Middleware);
    delete('/', (RequestContext req, res) {
      return req.parseQuery().then((query) {
        return this.remove(
            null,
            mergeMap([
              {'query': query},
              restProvider,
              req.serviceParams
            ]));
      });
    },
        middleware: []
          ..addAll(handlers)
          ..addAll(
              (removeMiddleware == null) ? [] : removeMiddleware.handlers));
    delete('/:id', (RequestContext req, res) {
      return req.parseQuery().then((query) {
        return this.remove(
            parseId(req.params['id']),
            mergeMap([
              {'query': query},
              restProvider,
              req.serviceParams
            ]));
      });
    },
        middleware: []
          ..addAll(handlers)
          ..addAll(
              (removeMiddleware == null) ? [] : removeMiddleware.handlers));

    // REST compliance
    put('/', () => throw new AngelHttpException.notFound());
    patch('/', () => throw new AngelHttpException.notFound());
  }

  /// Invoked when this service is wrapped within a [HookedService].
  void onHooked(HookedService hookedService) {}
}
