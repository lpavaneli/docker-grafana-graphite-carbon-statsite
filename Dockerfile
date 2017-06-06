FROM     ubuntu:14.04

# ---------------- #
#   Installation   #
# ---------------- #

ENV DEBIAN_FRONTEND noninteractive

USER root

#RUN apt-get remove python-openssl -yq 

# Update apt since the vagrant image might be old
RUN apt-get update -y

# Install package dependencies from apt
RUN apt-get install -y libcairo2-dev libffi-dev pkg-config python-dev python-pip fontconfig apache2 libapache2-mod-wsgi git-core memcached gcc g++ make libtool automake curl apt-transport-https supervisor

ADD . /usr/local/src

# Download source repositories for Graphite/Carbon/Whisper and Statsite
RUN cd /usr/local/src
RUN git clone https://github.com/graphite-project/graphite-web.git
RUN git clone https://github.com/graphite-project/carbon.git
RUN git clone https://github.com/graphite-project/whisper.git
RUN git clone https://github.com/armon/statsite.git

# Build and install Graphite/Carbon/Whisper and Statsite
RUN cd whisper; git checkout 1.0.0; python setup.py install
RUN cd ../carbon; git checkout 1.0.0; pip install -r requirements.txt; python setup.py install
RUN cd ../graphite-web; git checkout 1.0.0; pip install -r requirements.txt; python check-dependencies.py; python setup.py install
RUN cd ../statsite; ./autogen.sh; ./configure; make; cp statsite /usr/local/sbin/; cp sinks/graphite.py /usr/local/sbin/statsite-sink-graphite.py

# Update txamqp to support RabbitMQ 2.4+
RUN pip install txamqp==0.6.2 --upgrade

# Install configuration files for Graphite/Carbon and Apache
ADD ./master/templates/statsite/statsite.conf /etc/statsite.conf
ADD ./master/templates/graphite/conf/* /opt/graphite/conf/
ADD ./master/templates/apache/graphite.conf /etc/apache2/sites-available/
ADD ./master/templates/init/* /etc/init/
ADD ./master/templates/init.d/* /etc/init.d/

# Setup the correct Apache site and modules
RUN a2dissite 000-default
RUN a2ensite graphite
RUN a2enmod ssl
RUN a2enmod socache_shmcb
RUN a2enmod rewrite

# Install configuration files for Django
ADD ./master/templates/graphite/webapp/* /opt/graphite/webapp/graphite/
RUN sed -i -e "s/UNSAFE_DEFAULT/`date | md5sum | cut -d ' ' -f 1`/" /opt/graphite/webapp/graphite/local_settings.py

# Setup the Django database
RUN PYTHONPATH=/opt/graphite/webapp django-admin.py migrate --noinput --settings=graphite.settings --run-syncdb
RUN PYTHONPATH=/opt/graphite/webapp django-admin.py loaddata --settings=graphite.settings initial_data.json

# Add carbon system user and set permissions
RUN groupadd -g 998 carbon
RUN useradd -c "carbon user" -g 998 -u 998 -s /bin/false carbon
RUN chmod 775 /opt/graphite/storage
RUN chown www-data:carbon /opt/graphite/storage
RUN chown www-data:www-data /opt/graphite/storage/graphite.db
RUN chown -R carbon /opt/graphite/storage/whisper
RUN mkdir /opt/graphite/storage/log/apache2
RUN chown -R www-data /opt/graphite/storage/log/webapp
RUN chmod +x /etc/init.d/carbon-cache

# Setup hourly cron to rebuild Graphite index
ADD ./master/templates/graphite/cron/build-index /etc/cron.hourly/graphite-build-index
RUN chmod 755 /etc/cron.hourly/graphite-build-index
RUN sudo -u www-data /opt/graphite/bin/build-index.sh

# Install Grafana
RUN echo 'deb https://packagecloud.io/grafana/stable/debian/ wheezy main' > /etc/apt/sources.list.d/grafana.list
RUN curl https://packagecloud.io/gpg.key | apt-key add -
RUN apt-get update -y
RUN apt-get install -y grafana

RUN mkdir -p /opt/graphite/storage/grafana/data
RUN mkdir -p /opt/graphite/storage/grafana/log
RUN mkdir -p /opt/graphite/storage/grafana/dashboards
RUN chown grafana -R /opt/graphite/storage/grafana

# ----------------- #
#   Configuration   #
# ----------------- #

ADD     ./supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ---------------- #
#   Expose Ports   #
# ---------------- #

# Grafana
EXPOSE 3000
ADD 	./grafana.ini	/etc/grafana/grafana.ini

# Graphite
EXPOSE 80 
#ADD 	./graphite-api.yaml /etc/graphite-api.yaml

# Carbon
EXPOSE 2003 2004 7002
ADD	./carbon.conf /opt/graphite/conf/carbon.conf

VOLUME ["/opt/graphite/storage"]

# -------- #
#   Run!   #
# -------- #

CMD     ["/usr/bin/supervisord","-c","/etc/supervisor/conf.d/supervisord.conf"]
#CMD 	["/etc/init.d/influxdb","start"]
