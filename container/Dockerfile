FROM debian:stable
LABEL authors="matilde"

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y g++ libboost-random-dev libtiff-dev git make unzip catch2

RUN git clone https://github.com/afnantv27/Climate_Liberator.git Climate-Liberator

RUN cd Climate-Liberator/Cell2Fire && make

RUN chmod +x Climate-Liberator/Cell2Fire/Cell2Fire

ENTRYPOINT ["Climate-Liberator/Cell2Fire/Cell2Fire"]
