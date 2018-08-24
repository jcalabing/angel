library angel_orm_generator.test.models.role;

import 'package:angel_model/angel_model.dart';
import 'package:angel_orm/angel_orm.dart';
import 'package:angel_serialize/angel_serialize.dart';
part 'role.g.dart';
part 'role.serializer.g.dart';

@serializable
@postgreSqlOrm
class _Role extends Model {
  String name;
}