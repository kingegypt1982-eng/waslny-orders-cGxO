import { SetMetadata, createParamDecorator, ExecutionContext } from '@nestjs/common';

export const ROLES_KEY = 'roles';
export const Roles = (...roles: string[]) => SetMetadata(ROLES_KEY, roles);
export const CurrentUser = createParamDecorator((_data: unknown, context: ExecutionContext) =>
  context.switchToHttp().getRequest().user,
);