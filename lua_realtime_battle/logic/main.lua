
plugin{
	-- plugin name must be the same as folder name.
	name = 'gamebattle',

	-- depend any other plugin?
	dependencies = {
		'gameutils',
		'gameres',
	},

	-- entry function for plugin.
	main = function ( ... )
	
		importplugin('gameutils')
		importplugin('gameres')
		importplugin('model')

		use 'importclass'
		
	end,

}
