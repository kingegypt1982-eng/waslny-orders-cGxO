import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';

/**
 * Logs 500s with their full stack trace in the Nest logger.
 *
 * Client responses are unchanged: HttpExceptions keep their own status/body,
 * and unexpected errors become a generic 500. The stack never leaves the API.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse();
    const isHttpException = exception instanceof HttpException;
    const status = isHttpException
      ? exception.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;

    if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      const message = exception instanceof Error ? exception.message : String(exception);
      const stack = exception instanceof Error ? exception.stack : undefined;
      this.logger.error(
        `Unhandled ${status} error: ${message}`,
        stack ?? 'No stack trace available',
      );
    }

    const body = isHttpException
      ? exception.getResponse()
      : { statusCode: HttpStatus.INTERNAL_SERVER_ERROR, message: 'Internal server error' };
    return response.status(status).json(body);
  }
}
