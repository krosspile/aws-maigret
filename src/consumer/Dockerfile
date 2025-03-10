FROM python:slim

WORKDIR /app

COPY app.py app.py

COPY requirements.txt requirements.txt
RUN pip install -r requirements.txt

RUN pip install https://github.com/soxoj/maigret/archive/refs/heads/main.zip

CMD ["python", "app.py"]