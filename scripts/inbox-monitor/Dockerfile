FROM python:3.12-slim

# Disable Python output buffering for real-time logs
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir \
    icalendar \
    python-dateutil \
    psycopg2-binary \
    kubernetes

# Copy application files
COPY monitor.py .
COPY calendar_pg.py .
COPY scheduler_pg.py .
COPY idle_monitor.py .
COPY rsvp.py .

# Default command - use IDLE mode for push-based notifications
CMD ["python", "scheduler_pg.py", "--idle"]
