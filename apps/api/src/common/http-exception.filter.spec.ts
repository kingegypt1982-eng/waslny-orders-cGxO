import { ArgumentsHost, ConflictException } from '@nestjs/common';
import { AllExceptionsFilter } from './http-exception.filter';

function hostFor() {
  const json = jest.fn();
  const status = jest.fn().mockReturnValue({ json });
  const response = { status };
  const host = {
    switchToHttp: () => ({ getResponse: () => response, getRequest: () => ({ method: 'GET', url: '/test' }) }),
  } as unknown as ArgumentsHost;
  return { host, status, json };
}

describe('AllExceptionsFilter', () => {
  it('logs unexpected 500s with the stack trace but returns a generic body', () => {
    const filter = new AllExceptionsFilter();
    const errorSpy = jest.spyOn((filter as any).logger, 'error').mockImplementation(() => undefined);
    const { host, status, json } = hostFor();
    const error = new Error('db exploded');

    filter.catch(error, host);

    expect(status).toHaveBeenCalledWith(500);
    expect(json).toHaveBeenCalledWith({ statusCode: 500, message: 'Internal server error' });
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining('Unhandled 500 error: db exploded'),
      expect.stringContaining('Error: db exploded'),
    );
    errorSpy.mockRestore();
  });

  it('passes HttpExceptions through without logging them as 500s', () => {
    const filter = new AllExceptionsFilter();
    const errorSpy = jest.spyOn((filter as any).logger, 'error').mockImplementation(() => undefined);
    const { host, status, json } = hostFor();
    const exception = new ConflictException({ code: 'CONFLICT', message: 'Already taken' });

    filter.catch(exception, host);

    expect(status).toHaveBeenCalledWith(409);
    expect(json).toHaveBeenCalledWith(exception.getResponse());
    expect(errorSpy).not.toHaveBeenCalled();
    errorSpy.mockRestore();
  });
});
