from timvisher import aictl

ERROR = 1
USAGE = 2

HELP_SUGGESTION = "See 'timvisher_gh --help'"


class Exit(Exception):
    def __init__(self, status):
        super().__init__(status)
        self.status = status


def fail(code, message, *, status=ERROR, reason=None, suggestions=()):
    fields = {"code": code, "message": message, "suggestions": list(suggestions)}
    if reason:
        fields["reason"] = reason
    aictl.error(**fields)
    raise Exit(status)


def usage(message, *suggestions):
    fail("timvisher_gh_usage", message, status=USAGE, suggestions=[*suggestions, HELP_SUGGESTION])
